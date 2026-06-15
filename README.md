# Taxi — Sistema de asignación en tiempo real

Sistema de taxis con asignación concurrente de conductores, cancelaciones, penalizaciones y comunicación en tiempo real entre clientes y conductores.

## Stack

| Capa | Tecnologías |
|------|-------------|
| Backend | Elixir, Phoenix, GenServer, OTP, WebSockets |
| Frontend | React 19, Vite, Material UI, Phoenix Channels |
| Otros | Bandit, HTTPoison, UUID |

## Estructura

```
Taxi/
├── taxi_be/     # Backend Phoenix + GenServer
└── taxi_fe/     # Frontend React
```

## Funcionalidades

- Solicitud de viaje por parte del cliente
- Asignación concurrente a múltiples conductores candidatos
- Timeouts, cancelaciones y penalizaciones automáticas
- Comunicación en tiempo real vía Phoenix Channels
- Geolocalización y notificación de tarifa estimada

## Cómo ejecutar

### Backend

```bash
cd taxi_be
mix deps.get
mix phx.server
```

### Frontend

```bash
cd taxi_fe
npm install
npm run dev
```

## Contexto

Proyecto académico de **Implementación de métodos computacionales** (ITESM). Modelado con diagramas BPMN de flujos concurrentes.

## Autor

**Ángel Jiménez Morales** — [GitHub](https://github.com/angeljim17)
