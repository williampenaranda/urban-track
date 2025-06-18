# app/routers/paradas.py

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Dict

# Importar modelos y esquemas necesarios
from app.database import get_db
from app.models.entities import Parada, Ruta, RutaParada
from app.models.models import ParadaDetalleResponse, RutaEnParadaResponse

# GeoAlchemy2 y Shapely
from geoalchemy2.elements import WKBElement
from geoalchemy2.shape import to_shape

router = APIRouter()

@router.get("/cercanas-con-rutas", response_model=List[ParadaDetalleResponse])
async def get_paradas_cercanas_con_rutas(
    latitude: float = Query(..., description="Latitud actual del usuario"),
    longitude: float = Query(..., description="Longitud actual del usuario"),
    radius_meters: int = Query(300, description="Radio de búsqueda en metros"),
    db: Session = Depends(get_db)
):
    """
    Obtiene una lista de paradas que se encuentran dentro de un radio especificado
    (en metros) de una ubicación de usuario dada, incluyendo las rutas (ID y nombre)
    que pasan por cada parada.
    """
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise HTTPException(status_code=400, detail="Coordenadas de latitud/longitud inválidas.")
    if radius_meters <= 0:
        raise HTTPException(status_code=400, detail="El radio debe ser un valor positivo.")

    # Consulta para obtener paradas cercanas, uniendo explícitamente a RutaParada y Ruta.
    nearby_paradas_and_routes = db.query(Parada, Ruta) \
        .join(RutaParada, Parada.id == RutaParada.parada_id) \
        .join(Ruta, RutaParada.ruta_id == Ruta.id) \
        .filter(
            func.ST_DWithin(
                Parada.ubicacion,
                func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326),
                radius_meters,
                True
            )
        ).all()

    paradas_dict: Dict[int, Dict] = {} 

    for parada_obj, ruta_obj in nearby_paradas_and_routes:
        parada_id = parada_obj.id
        
        if parada_id not in paradas_dict:
            shapely_parada_point = to_shape(parada_obj.ubicacion)
            paradas_dict[parada_id] = {
                "id": parada_obj.id,
                "nombre": parada_obj.nombre,
                "latitude": shapely_parada_point.y,
                "longitude": shapely_parada_point.x,
                "rutas": []
            }
        
        paradas_dict[parada_id]["rutas"].append(RutaEnParadaResponse(
            id=ruta_obj.id,
            nombre=ruta_obj.nombre
        ))
    
    response_paradas = [ParadaDetalleResponse(**data) for data in paradas_dict.values()]
    
    return response_paradas