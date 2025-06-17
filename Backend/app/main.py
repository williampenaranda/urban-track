# app/main.py

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import engine, Base, get_db
# Importa solo las entidades necesarias aquí, como UserTrackingSession y Usuario
from app.models.entities import UserTrackingSession, UserLocationHistory, Usuario
from app.models.models import UserLocationUpdateWS
from app.services.clustering_service import clustering_service # Importa la instancia del servicio
from geoalchemy2.shape import to_shape, from_shape
from shapely.geometry import Point as ShapelyPoint
from datetime import datetime
from geoalchemy2.elements import WKBElement # <--- NEW ESSENTIAL IMPORT!
import shapely.wkb # <--- ¡CAMBIO AQUÍ!
import asyncio

# --- IMPORTS DE LOS ROUTERS ---
from app.rutas.tracking import router as tracking_router
from app.rutas.route_planning import router as route_planning_router # Asumiendo el nuevo nombre del archivo
from app.irregularities.routes import router as irregularities_router # Importa el router de irregularidades
from app.auth import routes as auth_routes


app = FastAPI(
    title="Transcaribe Tracking API",
    description="API para el seguimiento de buses y usuarios de Transcaribe y reporte de irregularidades.",
    version="0.1.0"
)

# --- INCLUIR LOS ROUTERS (Añadir/Modificar) ---
app.include_router(auth_routes.router, prefix="/api/auth", tags=["Autenticación"])
app.include_router(tracking_router, prefix="/api/tracking", tags=["Tracking"])
app.include_router(irregularities_router, prefix="/api/irregularities", tags=["Irregularidades"])
app.include_router(route_planning_router, prefix="/api/ruta", tags=["Rutas"])


# --- EVENTOS DE INICIO/APAGADO PARA CLUSTERING SERVICE (Añadir) ---
@app.on_event("startup")
async def startup_event():
    print("Iniciando la creación de tablas (si no existen)...")
    # Asegura que las tablas se creen ANTES de iniciar el servicio
    # Esto puede tomar un momento, pero es sincrónico aquí
    Base.metadata.create_all(bind=engine)
    print("Tablas verificadas/creadas.")

    # Puedes añadir un pequeño retraso aquí para mayor seguridad,
    # aunque create_all() debería ser sincrónico y bloquear hasta que termine.
    # await asyncio.sleep(1) # Opcional: Descomentar si aún experimentas el problema

    print("Aplicación iniciada. Iniciando ClusteringService...")
    clustering_service.start(get_db) # Pasa la función get_db al servicio
    print("ClusteringService iniciado.")

@app.on_event("shutdown")
async def shutdown_event():
    print("Aplicación cerrándose. Deteniendo ClusteringService...")
    clustering_service.stop()

# --- WEB SOCKET ENDPOINT (Añadir) ---
@app.websocket("/ws/location/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: int, db: Session = Depends(get_db)):
    """
    Endpoint WebSocket para que los usuarios envíen actualizaciones de su ubicación en tiempo real.
    Un usuario solo puede conectar si tiene una UserTrackingSession activa y está marcado como 'is_on_bus'.
    """
    user_session = db.query(UserTrackingSession).filter_by(user_id=user_id, status='active').first()
    if not user_session or not user_session.is_on_bus:
        print(f"Usuario {user_id} intentó conectar WebSocket sin sesión activa o no marcado 'is_on_bus'.")
        # Cierra la conexión si no cumple las condiciones
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    print(f"Cliente {user_id} conectado al WebSocket de ubicación.")
    try:
        while True:
            data = await websocket.receive_json()
            try:
                location_update = UserLocationUpdateWS(**data)
            except Exception as e:
                print(f"Error de validación de datos WS para {user_id}: {e}")
                await websocket.send_json({"error": "Invalid location data"})
                continue

            user_point_shapely = ShapelyPoint(location_update.longitude, location_update.latitude)

            # --- LA ASIGNACIÓN CON EL CAMBIO ---
            ubicacion_wkb_element = WKBElement(shapely.wkb.dumps(user_point_shapely, hex=False), srid=4326)

            new_location = UserLocationHistory(
                user_id=user_id,
                ubicacion=ubicacion_wkb_element, # Assign the WKBElement
                speed=location_update.speed,
                heading=location_update.heading,
                timestamp=datetime.utcnow()
            )
            # --------------------------

            db.add(new_location)
            db.commit()
            db.refresh(new_location)

            # Envía la actualización al servicio de clustering para procesamiento
            await clustering_service.add_location_update({
                "user_id": user_id,
                "location": {"lat": location_update.latitude, "lon": location_update.longitude},
                "speed": location_update.speed,
                "heading": location_update.heading,
                "timestamp": new_location.timestamp.isoformat()
            })

    except WebSocketDisconnect:
        print(f"Cliente {user_id} desconectado del WebSocket.")
    except Exception as e:
        print(f"Error inesperado en WebSocket para {user_id}: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Asegúrate de cerrar la sesión de DB
        db.close()