# app/services/clustering_service.py

import asyncio
import time
from collections import deque
from typing import List, Dict, Callable, Any, Optional
from datetime import datetime, timedelta
import uuid
from sqlalchemy.orm import Session
from sqlalchemy.sql import func
from shapely.geometry import Point as ShapelyPoint
from geoalchemy2.shape import from_shape, to_shape
from geoalchemy2.elements import WKBElement

from app.models.entities import UserTrackingSession, VirtualBus, Ruta, UserLocationHistory
from app.database import get_db # Importa get_db

class ClusteringService:
    def __init__(self):
        self.user_locations_queue = deque()
        self.virtual_buses: Dict[uuid.UUID, VirtualBus] = {}
        self.is_running = False
        self.processing_task: Optional[asyncio.Task] = None
        self.db_provider: Optional[Callable[[], Session]] = None

        # Configuración del clustering (ajustar según necesidades)
        self.MAX_DISTANCE_TO_ROUTE = 50  # Metros: Distancia máxima de un usuario a una ruta para ser considerado "en ruta"
        self.MAX_BUS_IDLE_TIME = timedelta(minutes=5) # Tiempo para desactivar un bus virtual si no hay actualizaciones
        self.MIN_USERS_FOR_BUS = 1 # Número mínimo de usuarios para considerar un bus virtual
        self.CLUSTER_RADIUS = 30 # Metros: Radio para agrupar usuarios en un bus virtual

    def start(self, db_provider: Callable[[], Session]):
        self.db_provider = db_provider
        self.is_running = True
        self.processing_task = asyncio.create_task(self._process_location_updates_periodically())
        print("ClusteringService iniciado.")

    def stop(self):
        self.is_running = False
        if self.processing_task:
            self.processing_task.cancel()
        print("ClusteringService detenido.")

    async def add_location_update(self, update: Dict[str, Any]):
        self.user_locations_queue.append(update)

    async def _process_location_updates_periodically(self):
        while self.is_running:
            try:
                await self._process_updates()
                await self._clean_inactive_buses()
            except asyncio.CancelledError:
                print("ClusteringService task cancelled.")
                break # Exit the loop cleanly on cancellation
            except Exception as e:
                print(f"Error en el ciclo de procesamiento del ClusteringService: {e}")
                import traceback
                traceback.print_exc()
            await asyncio.sleep(5) # Procesa cada 5 segundos (ajustable)

    async def _process_updates(self):
        if not self.user_locations_queue:
            return

        print(f"Procesando {len(self.user_locations_queue)} actualizaciones de ubicación...")
        updates_to_process = []
        while self.user_locations_queue:
            updates_to_process.append(self.user_locations_queue.popleft())

        user_data = {}

        # --- CAMBIO AQUÍ: Manejo manual de la sesión DB ---
        db: Session = next(self.db_provider()) # Obtener la sesión del generador
        try:
            # Recuperar datos de sesiones activas de los usuarios
            user_ids = {u["user_id"] for u in updates_to_process}
            active_sessions = db.query(UserTrackingSession).filter(
                UserTrackingSession.user_id.in_(list(user_ids)),
                UserTrackingSession.status == 'active'
            ).all()
            active_sessions_map = {session.user_id: session for session in active_sessions}

            # Procesar actualizaciones y construir datos de usuario
            for update in updates_to_process:
                user_id = update["user_id"]
                session = active_sessions_map.get(user_id)
                if not session or not session.is_on_bus:
                    continue

                user_point = ShapelyPoint(update["location"]["lon"], update["location"]["lat"])
                user_data[user_id] = {
                    "location": user_point,
                    "reported_route_id": session.reported_route_id,
                    "session": session,
                    "speed": update.get("speed", 0.0),
                    "heading": update.get("heading", 0.0)
                }

            # Obtener todas las rutas para verificación de geometría
            routes_in_use_ids = {u["reported_route_id"] for u in user_data.values() if u["reported_route_id"]}
            routes_map = {r.id: r for r in db.query(Ruta).filter(Ruta.id.in_(list(routes_in_use_ids))).all()}

            # Lógica de clustering principal
            self._perform_clustering(db, user_data, routes_map)

        finally:
            db.close() # Asegurarse de cerrar la sesión

    def _perform_clustering(self, db: Session, user_data: Dict[int, Dict[str, Any]], routes_map: Dict[int, Ruta]):
        # Paso 1: Agrupar usuarios por ruta reportada
        users_by_reported_route: Dict[int, List[Dict[str, Any]]] = {}
        for user_id, data in user_data.items():
            if data["reported_route_id"]:
                users_by_reported_route.setdefault(data["reported_route_id"], []).append(data)

        # Paso 2: Iterar por cada grupo de ruta y hacer clustering
        for route_id, users_in_route in users_by_reported_route.items():
            if not users_in_route:
                continue

            # Traer los buses virtuales existentes para esta ruta
            existing_buses = db.query(VirtualBus).filter(VirtualBus.route_id == route_id, VirtualBus.status == 'active').all()
            current_buses_map = {bus.id: bus for bus in existing_buses}

            # Asignar usuarios a buses existentes o crear nuevos clusters/buses
            assigned_user_ids = set()
            newly_created_buses = {} # Para evitar conflictos con current_buses_map

            for user in users_in_route:
                if user["session"].user_id in assigned_user_ids:
                    continue # Ya asignado a un bus

                best_bus_match: Optional[VirtualBus] = None
                min_distance = float('inf')

                # Buscar un bus virtual existente cercano
                for bus_id, bus in current_buses_map.items():
                    # Asegúrate de que 'ubicacion' sea un objeto Shapely Point para usar .distance
                    bus_point = to_shape(bus.ubicacion) if isinstance(bus.ubicacion, WKBElement) else bus.ubicacion
                    distance = user["location"].distance(bus_point) * 111320 # Convertir grados a metros aprox.
                    if distance < self.CLUSTER_RADIUS and distance < min_distance:
                        best_bus_match = bus
                        min_distance = distance

                if best_bus_match:
                    # Asignar usuario a bus existente
                    if user["session"].user_id not in best_bus_match.assigned_user_ids:
                        best_bus_match.assigned_user_ids.append(user["session"].user_id)
                    assigned_user_ids.add(user["session"].user_id)
                    user["session"].assigned_bus_id = best_bus_match.id
                    db.add(user["session"])
                else:
                    # Crear nuevo bus virtual si hay suficientes usuarios cerca O si es el primero
                    # Por simplicidad inicial: si no hay bus y el usuario está "en ruta", podría crear uno.
                    # Puedes refinar esta lógica si solo quieres crear buses con un mínimo de N usuarios.
                    if user["session"].user_id not in assigned_user_ids: # Asegurarse de que no fue asignado en este mismo ciclo a otro bus
                        # Verifica si el usuario está lo suficientemente cerca de la ruta que reportó
                        route_geom = routes_map.get(route_id)
                        if route_geom and isinstance(route_geom.geometria, WKBElement): # Asumiendo que Ruta.geometria existe y es WKBElement
                             route_line = to_shape(route_geom.geometria)
                             # distancia del punto del usuario a la línea de la ruta en metros
                             distance_to_route = user["location"].distance(route_line) * 111320
                             if distance_to_route < self.MAX_DISTANCE_TO_ROUTE:
                                new_bus_id = uuid.uuid4()
                                new_bus = VirtualBus(
                                    id=new_bus_id,
                                    route_id=route_id,
                                    ubicacion=from_shape(user["location"], srid=4326),
                                    current_speed=user["speed"],
                                    current_heading=user["heading"],
                                    assigned_user_ids=[user["session"].user_id],
                                    last_update=func.now(),
                                    status='active'
                                )
                                db.add(new_bus)
                                newly_created_buses[new_bus_id] = new_bus
                                assigned_user_ids.add(user["session"].user_id)
                                user["session"].assigned_bus_id = new_bus.id
                                db.add(user["session"])
                                print(f"Nuevo bus virtual {new_bus.id} creado en ruta {route_id} por usuario {user['session'].user_id}")
                             else:
                                 print(f"Usuario {user['session'].user_id} no asignado a bus: Demasiado lejos de la ruta reportada {route_id} ({distance_to_route:.2f}m).")
                        else:
                            print(f"Advertencia: No se encontró geometría para la ruta {route_id} o no es válida.")


            # Actualizar la ubicación de los buses existentes basados en los usuarios asignados
            for bus_id, bus in current_buses_map.items():
                users_on_this_bus = [u["location"] for u_id, u in user_data.items() if u["session"].assigned_bus_id == bus_id]
                if users_on_this_bus:
                    # Calcula el centroide o el promedio de las ubicaciones de los usuarios
                    centroid_x = sum(p.x for p in users_on_this_bus) / len(users_on_this_bus)
                    centroid_y = sum(p.y for p in users_on_this_bus) / len(users_on_this_bus)
                    bus.ubicacion = from_shape(ShapelyPoint(centroid_x, centroid_y), srid=4326)
                    bus.last_update = func.now()
                    # Puedes promediar velocidad y rumbo si es necesario
                # Limpiar usuarios desasignados del bus si ya no están activos o no tienen assigned_bus_id
                bus.assigned_user_ids = [
                    u_id for u_id in bus.assigned_user_ids
                    if u_id in user_data and user_data[u_id]["session"].assigned_bus_id == bus.id
                ]

                db.add(bus)

            db.commit() # Commit de todos los cambios de usuarios y buses virtuales
            print(f"Clustering completado para ruta {route_id}. Buses activos: {len(current_buses_map) + len(newly_created_buses)}")


    async def _clean_inactive_buses(self):
        db: Session = next(self.db_provider()) # Obtener la sesión del generador
        try:
            inactive_threshold = datetime.utcnow() - self.MAX_BUS_IDLE_TIME
            buses_to_deactivate = db.query(VirtualBus).filter(
                VirtualBus.status == 'active',
                VirtualBus.last_update < inactive_threshold
            ).all()

            for bus in buses_to_deactivate:
                # Comprobar si hay sesiones de usuario activas asignadas a este bus
                active_assigned_sessions = db.query(UserTrackingSession).filter(
                    UserTrackingSession.assigned_bus_id == bus.id,
                    UserTrackingSession.status == 'active',
                    UserTrackingSession.is_on_bus == True
                ).first() # Solo necesitamos verificar si existe al menos una

                if not active_assigned_sessions: # Si no hay sesiones activas asignadas, desactivar el bus
                    bus.status = 'inactive'
                    db.add(bus)
                    print(f"Bus virtual {bus.id} desactivado por inactividad y sin usuarios activos.")
                # else: El bus tiene usuarios activos asignados, no lo desactives solo por last_update

            # Además, limpia las asignaciones de bus en UserTrackingSession si el bus se ha inactivo
            # Esto es redundante si la lógica anterior maneja bien la desactivación,
            # pero asegura consistencia si un bus se desactiva por otros medios.
            sessions_with_inactive_bus = db.query(UserTrackingSession).join(VirtualBus).filter(
                UserTrackingSession.status == 'active',
                UserTrackingSession.is_on_bus == True,
                VirtualBus.status == 'inactive'
            ).all()
            for session in sessions_with_inactive_bus:
                session.assigned_bus_id = None
                session.is_on_bus = False # Ya no está en un bus
                db.add(session)
                print(f"Sesión de usuario {session.user_id} desasignada del bus inactivo {session.assigned_bus_id}.")


            db.commit()

        finally:
            db.close() # Asegurarse de cerrar la sesión

# Instancia global del servicio
clustering_service = ClusteringService()