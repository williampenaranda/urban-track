
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional # Asegúrate de que List y Optional estén importados
from app.database import get_db
# Asegúrate de que las importaciones de entidades y modelos sean correctas para lo que MANTIENES
from app.models.entities import Ruta, Parada # Solo las entidades que uses en este archivo
from app.services.route_calculation import calcular_trayecto_usuario
from app.services import route_info_service # Si lo usas aquí

from app.models.models import (
    SimplifiedCalculatedRouteResponse,
    CalculateRouteRequest,
    # Asegúrate de importar RutaDetalleResponse, UbicacionResponse, ParadaEnRutaResponse
    # si los necesitas para los endpoints /rutas
    RutaDetalleResponse,
    # ... otros modelos de respuesta si los tienes para rutas
)

router = APIRouter()

# --- Configuración para la tarea de fondo de cálculo de buses (Recordatorio) ---
# Este bloque no va en este archivo, sino en tu `main.py` de FastAPI.
# Es un recordatorio de cómo iniciar el hilo para `run_bus_tracking_periodically`.
"""
Ejemplo de cómo iniciar la tarea de fondo en tu main.py:

from threading import Thread
import time 

# ... tus imports de FastAPI, routers, get_db, etc.

@app.on_event("startup")
async def startup_event():
    print("Iniciando tarea de cálculo de buses en segundo plano...")
    background_thread = Thread(target=run_bus_tracking_periodically, args=(get_db,))
    background_thread.daemon = True 
    background_thread.start()
    print("Tarea de cálculo de buses iniciada.")

"""
# Fin del ejemplo de configuración de tarea de fondo.




# --- ENDPOINT para calcular la ruta ---
@router.post(
    "/calculate_route",
    status_code=status.HTTP_200_OK,
    # ¡LA CORRECCIÓN ESTÁ AQUÍ! Cambia CalculateRouteResponse por SimplifiedCalculatedRouteResponse
    response_model=SimplifiedCalculatedRouteResponse 
)
async def calculate_user_route(request: CalculateRouteRequest, db: Session = Depends(get_db)):
    """
    Calcula el trayecto más adecuado para el usuario entre dos puntos geográficos.
    """
    try:
        suggested_route = await calcular_trayecto_usuario(
            db,
            request.origen_lat,
            request.origen_lon,
            request.destino_lat,
            request.destino_lon
        )
        if suggested_route:
            return suggested_route
        else:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No se pudo calcular una ruta para las ubicaciones proporcionadas."
            )
    except Exception as e:
        print(f"Error al calcular la ruta: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno al calcular la ruta: {e}"
        )


# --- NUEVOS ENDPOINTS PARA INFORMACIÓN DE RUTAS ---

@router.get("/rutas", response_model=List[RutaDetalleResponse])
def get_all_transcaribe_routes(db: Session = Depends(get_db)):
    """
    Obtiene una lista de todas las rutas de Transcaribe con sus detalles, incluyendo las paradas.
    """
    routes = route_info_service.get_all_routes(db)
    return routes

@router.get("/rutas/{route_id}", response_model=RutaDetalleResponse)
def get_transcaribe_route_by_id(route_id: int, db: Session = Depends(get_db)):
    """
    Obtiene los detalles de una ruta específica de Transcaribe por su ID.
    """
    route = route_info_service.get_route_by_id(db, route_id)
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Ruta con ID {route_id} no encontrada."
        )
    return route