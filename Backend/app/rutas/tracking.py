# app/routers/tracking.py

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from app.database import get_db
from app.models.entities import UserTrackingSession, VirtualBus, Usuario, Ruta
from app.models.models import UserTrackingStartRequest, UserTrackingStopRequest, UserSetOnBusRequest, BusLocationResponse
from geoalchemy2.shape import to_shape # Necesario para convertir la geometría a lat/lon

# Crea una instancia de APIRouter con prefijo y tags
router = APIRouter()

@router.post("/start-session", summary="Iniciar una sesión de seguimiento para un usuario")
async def start_user_tracking_session(request: UserTrackingStartRequest, db: Session = Depends(get_db)):
    """
    Inicia una sesión de seguimiento para un usuario.
    Permite al usuario indicar opcionalmente la ruta que planea tomar.
    Si ya hay una sesión activa, la actualiza.
    """
    user = db.query(Usuario).filter_by(id=request.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    # Busca una sesión activa para este usuario
    session = db.query(UserTrackingSession).filter_by(user_id=request.user_id, status='active').first()
    if session:
        # Si ya existe una sesión activa, solo actualiza la ruta seleccionada
        session.selected_route_id = request.selected_route_id
        db.add(session)
        db.commit()
        db.refresh(session)
        return {"message": "Sesión de seguimiento actualizada", "session_id": session.id}

    # Si no hay sesión activa, crea una nueva
    new_session = UserTrackingSession(
        user_id=request.user_id,
        selected_route_id=request.selected_route_id,
        is_on_bus=False, # Inicialmente no está en un bus
        status='active'
    )
    db.add(new_session)
    db.commit()
    db.refresh(new_session)
    return {"message": "Sesión de seguimiento iniciada", "session_id": new_session.id}

@router.post("/set-on-bus", summary="Usuario indica que está a bordo de un bus")
async def set_user_on_bus(request: UserSetOnBusRequest, db: Session = Depends(get_db)):
    """
    Permite a un usuario notificar al sistema que está físicamente a bordo de un bus,
    indicando la ruta que ha reportado tomar.
    Esto es crucial para que el ClusteringService lo asigne a un bus virtual.
    """
    session = db.query(UserTrackingSession).filter_by(user_id=request.user_id, status='active').first()
    if not session:
        raise HTTPException(status_code=400, detail="Sesión de seguimiento no activa. Inicie una sesión primero.")

    route = db.query(Ruta).filter_by(id=request.reported_route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail=f"Ruta con ID {request.reported_route_id} no encontrada.")

    session.is_on_bus = True
    session.reported_route_id = request.reported_route_id
    db.add(session)
    db.commit()
    db.refresh(session)
    return {"message": f"Usuario {request.user_id} marcado como 'a bordo' de la ruta {request.reported_route_id}"}

@router.post("/stop-session", summary="Detener una sesión de seguimiento de un usuario")
async def stop_user_tracking_session(request: UserTrackingStopRequest, db: Session = Depends(get_db)):
    """
    Detiene una sesión de seguimiento activa para un usuario.
    También desasigna al usuario de cualquier bus virtual.
    """
    session = db.query(UserTrackingSession).filter_by(user_id=request.user_id, status='active').first()
    if not session:
        raise HTTPException(status_code=404, detail="Sesión de seguimiento no encontrada o ya inactiva")

    session.status = 'ended'
    session.end_time = datetime.utcnow()
    session.is_on_bus = False # Ya no está en un bus
    session.assigned_bus_id = None # Desasigna del bus virtual
    db.add(session)
    db.commit()
    return {"message": "Sesión de seguimiento detenida"}

@router.get("/active-buses", response_model=List[BusLocationResponse], summary="Obtener la ubicación de todos los buses virtuales activos")
async def get_active_virtual_buses(route_id: Optional[int] = None, db: Session = Depends(get_db)):
    """
    Recupera la información de todos los buses virtuales actualmente activos en el sistema.
    Opcionalmente filtra por ID de ruta.
    """
    query = db.query(VirtualBus).filter(VirtualBus.status == 'active')
    if route_id:
        query = query.filter(VirtualBus.route_id == route_id)

    virtual_buses = query.all()

    response_buses = []
    for bus in virtual_buses:
        # Convertir la geometría de la DB a latitud y longitud para la respuesta Pydantic
        point = to_shape(bus.ubicacion)
        response_buses.append(BusLocationResponse(
            id=bus.id,
            route_id=bus.route_id,
            latitude=point.y, # Latitud
            longitude=point.x, # Longitud
            current_speed=bus.current_speed,
            current_heading=bus.current_heading,
            assigned_user_ids=bus.assigned_user_ids,
            last_update=bus.last_update,
            status=bus.status
        ))
    return response_buses

@router.get("/bus/{bus_id}/status", response_model=BusLocationResponse, summary="Obtener el estado de un bus virtual específico")
async def get_virtual_bus_status(bus_id: UUID, db: Session = Depends(get_db)):
    """
    Obtiene el estado detallado de un bus virtual específico por su ID.
    """
    virtual_bus = db.query(VirtualBus).filter_by(id=bus_id).first()
    if not virtual_bus:
        raise HTTPException(status_code=404, detail="Bus virtual no encontrado")

    point = to_shape(virtual_bus.ubicacion)
    return BusLocationResponse(
        id=virtual_bus.id,
        route_id=virtual_bus.route_id,
        latitude=point.y,
        longitude=point.x,
        current_speed=virtual_bus.current_speed,
        current_heading=virtual_bus.current_heading,
        assigned_user_ids=virtual_bus.assigned_user_ids,
        last_update=virtual_bus.last_update,
        status=virtual_bus.status
    )

@router.get("/bus/{bus_id}/route", summary="Obtener los detalles de la ruta de un bus virtual")
async def get_virtual_bus_route_details(bus_id: UUID, db: Session = Depends(get_db)):
    """
    Obtiene los detalles de la ruta asociada a un bus virtual específico.
    """
    virtual_bus = db.query(VirtualBus).filter_by(id=bus_id).first()
    if not virtual_bus:
        raise HTTPException(status_code=404, detail="Bus virtual no encontrado")

    route_details = db.query(Ruta).filter_by(id=virtual_bus.route_id).first()
    if not route_details:
        # Esto no debería pasar si la relación ForeignKey es correcta, pero es una buena salvaguarda
        raise HTTPException(status_code=404, detail="Detalles de la ruta no encontrados para este bus virtual")

    return {
        "route_id": route_details.id,
        "nombre": route_details.nombre,
        "descripcion": route_details.descripcion,
    }