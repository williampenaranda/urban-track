# app/services/clustering_service.py

import asyncio
import time
from collections import deque
from typing import List, Dict, Callable, Any, Optional
from datetime import datetime, timedelta
import uuid
from sqlalchemy.orm import Session, relationship, joinedload
from sqlalchemy.sql import func

from geoalchemy2.shape import from_shape, to_shape
from geoalchemy2.elements import WKBElement

from app.database import get_db # Importa get_db
from app.models.entities import UserTrackingSession, VirtualBus, Ruta, UserLocationHistory, Parada, RutaParada
import collections
import numpy as np
from shapely.geometry import Point, LineString # Asegúrate de importar LineString
import shapely.wkb # Para shapely.wkb.dumps si lo usas en main.py, si no, puedes quitarlo.

# Asegúrate de importar todos tus modelos de entidades relevantes
from app.models.entities import UserTrackingSession, VirtualBus, Ruta, UserLocationHistory, Parada, RutaParada
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
        self.MAX_CLUSTER_DISTANCE = 50 # Metros: Distancia máxima para agrupar usuarios en un bus existente

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
        # Este print es para depuración y confirma que el ciclo se ejecuta
        print(f"[{datetime.now().strftime('%H:%M:%S')}] ClusteringService: Procesando ciclo...")

        if not self.user_locations_queue:
            # print("No hay actualizaciones de ubicación en la cola. Saltando el procesamiento.") # Puedes activar esto para depuración
            return

        print(f"Procesando {len(self.user_locations_queue)} actualizaciones de ubicación...")

        # Mapeo temporal para acumular actualizaciones por usuario y obtener la más reciente
        user_latest_updates = collections.defaultdict(dict)
        while self.user_locations_queue:
            update = self.user_locations_queue.popleft()
            user_latest_updates[update['user_id']] = update

        db: Session = next(self.db_provider())
        try:
            # Cargar las rutas, y para cada ruta, cargar sus RutaParada ordenadas y las Paradas asociadas.
            # Esto usa eager loading (joinedload) para evitar el problema de N+1 queries,
            # lo que mejora mucho el rendimiento.
            routes_map = {route.id: route for route in db.query(Ruta).options(
                joinedload(Ruta.paradas).joinedload(RutaParada.parada) # <-- ¡ASÍ ES LA SINTAXIS CORRECTA!
            ).all()}

            for user_id, user_data in user_latest_updates.items():
                self._perform_clustering(db, user_data, routes_map)

            # Limpiar buses inactivos periódicamente
            await self._clean_inactive_buses()

        except Exception as e:
            db.rollback()
            print(f"Error en _process_updates: {e}")
            import traceback
            traceback.print_exc()
        finally:
            db.close()


    def _perform_clustering(self, db: Session, user_data: Dict, routes_map: Dict):
        user_id = user_data["user_id"]
        location_data = user_data["location"]
        
        # Obtener la sesión de seguimiento del usuario
        user_session = db.query(UserTrackingSession).filter(
            UserTrackingSession.user_id == user_id,
            UserTrackingSession.status == 'active',
            UserTrackingSession.is_on_bus == True
        ).first()

        if not user_session:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} sin sesión activa con is_on_bus=True. Saltando clustering.")
            return

        user_location_point = Point(location_data["lon"], location_data["lat"]) # Objeto Shapely Point

        route_id = user_session.selected_route_id # O user_session.reported_route_id, según tu lógica de negocio
        if not route_id:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} con sesión activa pero sin ruta seleccionada/reportada. Saltando clustering.")
            return

        ruta_obj: Ruta = routes_map.get(route_id)
        if not ruta_obj:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Ruta {route_id} no encontrada en el mapa de rutas para clustering de usuario {user_id}. Saltando clustering.")
            return

        # 1. Obtener las RutaParada asociadas a la ruta y ordenarlas por el campo 'orden'.
        # 2. Extraer las ubicaciones de las Paradas y construir la LineString.
        ordered_paradas_shapely_points: List[Point] = []
        
        # Ordenamos las instancias de RutaParada por su atributo 'orden'.
        sorted_ruta_paradas: List[RutaParada] = sorted(ruta_obj.paradas, key=lambda rp: rp.orden)

        for ruta_parada_entry in sorted_ruta_paradas:
            parada_obj: Parada = ruta_parada_entry.parada # Accede al objeto Parada real
            if parada_obj and parada_obj.ubicacion:
                # 'ubicacion' en Parada es un Geometry(POINT), que GeoAlchemy2 carga como WKBElement.
                # Usamos to_shape para convertir el WKBElement a un objeto Shapely Point.
                shapely_point: Point = to_shape(parada_obj.ubicacion)
                ordered_paradas_shapely_points.append(shapely_point)
            else:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Advertencia: Parada con ID {ruta_parada_entry.parada_id} de ruta {route_id} no tiene ubicación válida.")

        # --- Inicializar route_line_geometry a None ANTES de intentar construirla ---
        route_line_geometry: LineString = None 
        # -------------------------------------------------------------------------

        if len(ordered_paradas_shapely_points) >= 2:
            try:
                # Crear una LineString de Shapely si hay al menos dos puntos ordenados
                route_line_geometry = LineString(ordered_paradas_shapely_points)
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Geometría de línea para ruta {route_id} creada a partir de {len(ordered_paradas_shapely_points)} paradas.")
            except Exception as e:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Error al crear LineString para ruta {route_id} desde paradas: {e}. Geometría no disponible.")
                route_line_geometry = None 
        
        if not route_line_geometry:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: No se pudo construir una geometría de línea válida para la ruta {route_id} desde sus paradas. Saltando clustering para esta ruta.")
            return 

        # --- Lógica de Clustering para buscar/crear bus ---
        
        # Calcular distancia del usuario a la LineString de la ruta (útil para depuración o validación)
        distance_to_route_m = user_location_point.distance(route_line_geometry) * 111320
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} ({location_data['lat']:.4f}, {location_data['lon']:.4f}) a {distance_to_route_m:.2f} metros de la ruta {route_id}.")


        assigned_bus = None
        min_distance = self.MAX_CLUSTER_DISTANCE # Umbral de distancia para agrupar

        # 1. Intentar encontrar un bus activo existente para esta ruta
        current_buses = db.query(VirtualBus).filter(
            VirtualBus.route_id == route_id,
            VirtualBus.status == 'active'
        ).all()

        # Si el usuario ya tiene un bus asignado en su sesión, intentamos usarlo si sigue activo
        if user_session.assigned_bus_id:
            existing_assigned_bus_in_db = next((bus for bus in current_buses if bus.id == user_session.assigned_bus_id), None)
            if existing_assigned_bus_in_db:
                assigned_bus = existing_assigned_bus_in_db
                # Opcional: Re-validar si el usuario sigue cerca de SU bus asignado
                bus_location = to_shape(assigned_bus.ubicacion)
                distance = user_location_point.distance(bus_location) * 111320
                if distance < self.MAX_CLUSTER_DISTANCE * 2: # Un umbral más flexible para mantener asignación
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} mantiene asignación a bus {assigned_bus.id}. Distancia: {distance:.2f}m.")
                    # Actualizar ubicación del bus virtual (ej. promedio de usuarios) - aquí simplificado
                    assigned_bus.ubicacion = WKBElement(shapely.wkb.dumps(user_location_point, hex=False), srid=4326)
                    assigned_bus.last_update = datetime.utcnow()
                    db.add(assigned_bus)
                    db.commit() # ¡Commit individual para esta actualización si sales aquí!
                    return # Si el usuario ya está asignado y se actualizó, podemos salir.
                else:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} demasiado lejos de su bus asignado {assigned_bus.id} ({distance:.2f}m). Buscando nuevo bus o creando uno.")
                    user_session.assigned_bus_id = None # Desasignar temporalmente para buscar un nuevo bus
                    db.add(user_session) # Guardar el cambio de desasignación
                    # Continuar para buscar/crear un nuevo bus
            else:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Bus asignado {user_session.assigned_bus_id} para usuario {user_id} no encontrado/activo. Buscando nuevo bus o creando uno.")
                user_session.assigned_bus_id = None # Limpiar el ID si el bus ya no existe/activo
                db.add(user_session)


        # 2. Si no se mantuvo la asignación, buscar el bus activo más cercano o crear uno nuevo
        if not assigned_bus: # Solo si no fue asignado por la lógica anterior
            for bus in current_buses:
                if bus.ubicacion:
                    bus_location = to_shape(bus.ubicacion)
                    distance = user_location_point.distance(bus_location) * 111320 # Distancia en metros
                    
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Comparando usuario {user_id} con bus {bus.id}. Distancia: {distance:.2f}m.")

                    if distance < min_distance:
                        assigned_bus = bus
                        min_distance = distance

        # 3. Asignar usuario a bus existente o crear uno nuevo
        if assigned_bus:
            # Asignar usuario a bus existente (si no estaba ya en la lista de assigned_user_ids)
            if user_id not in assigned_bus.assigned_user_ids:
                assigned_bus.assigned_user_ids.append(user_id)
                db.add(assigned_bus) # Marcar para guardar el cambio en assigned_user_ids
                print(f"[{datetime.now().strftime('%H:%M:%S')}] *** Clustering: Usuario {user_id} ASIGNADO a bus virtual {assigned_bus.id} en ruta {route_id}.***")
            else:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Usuario {user_id} YA ESTÁ EN la lista de asignados del bus {assigned_bus.id}.")
            
            # Siempre actualiza el timestamp y la ubicación del bus si hay actividad relevante
            assigned_bus.ubicacion = WKBElement(shapely.wkb.dumps(user_location_point, hex=False), srid=4326)
            assigned_bus.last_update = datetime.utcnow()
            db.add(assigned_bus)

            # Actualiza la sesión del usuario con el bus asignado si es necesario
            if user_session.assigned_bus_id != assigned_bus.id: # Solo si cambió o estaba nulo
                user_session.assigned_bus_id = assigned_bus.id
                db.add(user_session)
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Actualizando UserTrackingSession de {user_id} con assigned_bus_id: {assigned_bus.id}")

        else:
            # Crear un nuevo bus virtual
            new_bus = VirtualBus(
                route_id=route_id,
                ubicacion=WKBElement(shapely.wkb.dumps(user_location_point, hex=False), srid=4326), # Ubicación inicial del bus es la del usuario
                assigned_user_ids=[user_id],
                last_update=datetime.utcnow(),
                status='active'
            )
            db.add(new_bus)
            db.flush() # Para que new_bus.id se genere antes del commit
            print(f"[{datetime.now().strftime('%H:%M:%S')}] *** Clustering: NUEVO bus virtual {new_bus.id} CREADO en ruta {route_id} por usuario {user_id}.***")

            # Actualizar la sesión del usuario con el bus recién creado
            user_session.assigned_bus_id = new_bus.id
            db.add(user_session)
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering: Actualizando UserTrackingSession de {user_id} con assigned_bus_id: {new_bus.id}")

        db.commit() # Confirmar todos los cambios en esta transacción
        
        # Recargar buses activos para el mensaje final (o contar los que ya tenemos)
        final_active_buses_count = len(db.query(VirtualBus).filter_by(status='active', route_id=route_id).all())
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Clustering completado para ruta {route_id}. Total de buses activos en ruta: {final_active_buses_count}")




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