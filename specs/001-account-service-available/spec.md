# Spec 001 — Dejar el servicio de cuentas disponible

## Contexto y objetivo
La tienda y el panel necesitan poder usar el servicio de cuentas como parte de la aplicación completa. Este repositorio es el que deja ese servicio disponible junto al resto, sin definir cómo se entra ni qué se ve en pantalla. Sin esa disponibilidad, la tienda y el panel no pueden apoyarse en cuentas aunque el resto de la aplicación esté en marcha.

## Usuarios / actores
- Quien opera o despliega la aplicación (deja el servicio de cuentas disponible junto al resto).
- La tienda (consume el servicio de cuentas cuando está disponible).
- El panel (consume el servicio de cuentas cuando está disponible).

## Historias de usuario
- H1: Como operador de la aplicación quiero dejar el servicio de cuentas disponible junto al resto para que la tienda y el panel puedan usarlo.
- H2: Como tienda quiero poder alcanzar el servicio de cuentas cuando la aplicación está en marcha para apoyarme en él sin depender de otra vía improvisada.
- H3: Como panel quiero poder alcanzar el servicio de cuentas cuando la aplicación está en marcha para apoyarme en él sin depender de otra vía improvisada.

## Requisitos funcionales (criterios de aceptación en EARS)
- RF-1: EL SISTEMA dejará el servicio de cuentas disponible junto al resto de la aplicación.
- RF-2: CUANDO la aplicación esté en marcha con el resto de sus piezas, EL SISTEMA permitirá que la tienda use el servicio de cuentas.
- RF-3: CUANDO la aplicación esté en marcha con el resto de sus piezas, EL SISTEMA permitirá que el panel use el servicio de cuentas.
- RF-4: EL SISTEMA no definirá cómo se entra ni qué se ve en pantalla en la tienda o en el panel.
- RF-5: SI el servicio de cuentas no queda disponible, ENTONCES EL SISTEMA hará fallar la misma comprobación automática que cubre al resto e indicará que el servicio de cuentas no está disponible.

## Requisitos no funcionales
- El servicio de cuentas quedará disponible en desarrollo local y en el despliegue previsto fuera de local, junto al resto de la aplicación.
- Quedará expuesto igual que el resto de las APIs públicas, para que la tienda y el panel puedan usarlo sin un paso distinto al del resto.
- La misma comprobación automática que cubre al resto también cubrirá al servicio de cuentas.

## Casos límite
- Arranque o despliegue del resto de la aplicación sin que el servicio de cuentas quede usable: la comprobación automática falla e indica que el servicio de cuentas no está disponible (RF-5).
- La comprobación automática del resto no incluye al servicio de cuentas: no cumple este corte.

## Fuera de alcance
- La cuenta y el acceso con Google de la tienda (responsabilidad de fes-account-api).
- Las pantallas de la tienda (responsabilidad de fes-client-web).
- La puerta del panel (responsabilidad de fes-panel-api).
- Las pantallas del panel (responsabilidad de fes-panel-web).
- Decidir cómo se entra o qué se ve en pantalla.
- Cambiar el comportamiento de negocio del servicio de cuentas, de la tienda o del panel.

## Criterios de finalización
- Todos los RF verificables en verde según el criterio de cada uno.
- Demostración de que, con la aplicación en marcha, el servicio de cuentas está disponible junto al resto y es usable desde la tienda y desde el panel.
- Ningún criterio de esta spec exige implementar pantallas ni flujos de acceso.

## Dudas abiertas
No quedan dudas abiertas.
