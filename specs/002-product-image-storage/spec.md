# Spec 002 — Almacenamiento de imágenes de producto en MinIO y cableado

## Contexto y objetivo

Las imágenes de producto necesitan un almacenamiento compatible con S3 dentro del clúster. En Minikube, MinIO ya corre en el namespace `platform` (StatefulSet `minio`, servicio `minio.platform.svc.cluster.local:9000`) y la NetworkPolicy `platform-ingress` ya permite el puerto 9000 desde `apps`. Falta el bucket `product-images`, las credenciales dedicadas que usará catalog-api, el respaldo de los objetos en la ruta local del nodo Minikube y la URL interna de catalog-api en panel-api. El bucket se crea de forma idempotente con un script del repositorio en Minikube; las credenciales y la configuración de la ruta local son manuales y quedan documentadas en `docs/product-images.md`, no asumidas por la generación de código.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- catalog-api, que consume el endpoint S3, el bucket y las credenciales dedicadas.
- panel-api, que consume la URL interna de catalog-api.
- MinIO, que almacena los objetos.

## Historias de usuario

- H1: Como operador quiero que exista el bucket `product-images` para que catalog-api guarde las imágenes de producto.
- H2: Como operador quiero que en Minikube los objetos de MinIO se respalden en la ruta local del nodo para no perder las imágenes al recrear el clúster.
- H3: Como catalog-api quiero recibir el endpoint, el bucket y las credenciales S3 del entorno para subir y leer imágenes sin configuración manual dentro del servicio.
- H4: Como panel-api quiero conocer la URL interna de catalog-api para reenviar las operaciones de catálogo.
- H5: Como operador quiero una guía con la configuración manual de la ruta local, el bucket y las credenciales para reproducir el entorno sin adivinar valores.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: EL SISTEMA dispondrá del bucket `product-images` para almacenar las imágenes de producto.
- RF-2: CUANDO se aprovisione el entorno Minikube, EL SISTEMA creará el bucket `product-images` de forma idempotente mediante un script del repositorio.
- RF-3: DONDE el entorno sea Minikube, EL SISTEMA respaldará los objetos de MinIO en la ruta local `/friendly-e-shop/media/images` del nodo, reutilizando el montaje existente del workspace.
- RF-4: SI la ruta local `/friendly-e-shop/media/images` no existe, ENTONCES EL SISTEMA la creará vacía sin impedir el despliegue.
- RF-5: EL SISTEMA entregará a catalog-api la variable `S3_ENDPOINT` con la dirección del API S3 de MinIO del entorno (`http://minio.platform.svc.cluster.local:9000`).
- RF-6: EL SISTEMA entregará a catalog-api la variable `S3_BUCKET` con el valor `product-images`.
- RF-7: EL SISTEMA entregará a catalog-api la variable `S3_ACCESS_KEY` con la clave de acceso dedicada de las imágenes de producto.
- RF-8: EL SISTEMA entregará a catalog-api la variable `S3_SECRET_KEY` con la clave secreta dedicada de las imágenes de producto.
- RF-9: EL SISTEMA usará, para las imágenes de producto, credenciales dedicadas con una política limitada al bucket `product-images`, distintas de las credenciales raíz de MinIO.
- RF-10: EL SISTEMA entregará a panel-api la variable `CATALOG_API_BASE_URL` con el valor `http://catalog-api.apps.svc.cluster.local:8080`.
- RF-11: MIENTRAS el entorno esté desplegado, EL SISTEMA permitirá a los pods del namespace `apps` alcanzar el puerto 9000 de MinIO en el namespace `platform` mediante la política `platform-ingress`.
- RF-12: EL SISTEMA incluirá en `docs/product-images.md` la configuración manual de la ruta local, el bucket y las credenciales.
- RF-13: SI faltan el bucket o las credenciales de imágenes en el entorno, ENTONCES EL SISTEMA no inventará valores y el operador deberá completarlos según `docs/product-images.md`.
- RF-14: CUANDO se vuelva a desplegar Minikube, EL SISTEMA conservará en la ruta local reservada las imágenes ya almacenadas en MinIO.
- RF-15: DONDE el entorno sea Hostinger, EL SISTEMA respaldará las imágenes en el PVC de MinIO y entregará las credenciales dedicadas mediante un secret.

## Requisitos no funcionales

- La ruta local `/friendly-e-shop/media/images` es específica de Minikube en macOS; ningún otro entorno debe depender de ella.
- Las credenciales de las imágenes de producto son configuración manual y no deben asumirse ni codificarse en la generación de código.
- Las credenciales de imágenes no deben quedar en claro en el repositorio ni en plantillas desplegables; en Hostinger viajan cifradas con SOPS.
- El aprovisionamiento del bucket debe ser idempotente: repetirlo no debe crear duplicados ni fallar.
- El aprovisionamiento debe seguir la estructura base/overlay del repositorio y no duplicar manifiestos completos entre Minikube y Hostinger.

## Casos límite

- La ruta local reservada no existe o está vacía: no debe impedir el despliegue; el respaldo simplemente no contendrá imágenes todavía.
- El bucket `product-images` ya existe: el aprovisionamiento no debe crear un duplicado ni fallar.
- Las credenciales de imágenes no están definidas: catalog-api no dispondrá de `S3_ACCESS_KEY` ni `S3_SECRET_KEY` válidos y el despliegue no debe inventarlas.
- MinIO no está listo cuando arranca catalog-api: la indisponibilidad momentánea del API S3 no debe corromper datos.
- Recrear el clúster Minikube: los objetos de MinIO deben seguir en la ruta local reservada y volver a montarse.
- Un entorno distinto de Minikube (Hostinger): las imágenes se respaldan en el PVC de MinIO y las credenciales dedicadas llegan por secret cifrado.

## Fuera de alcance

- Definir el esquema de productos, sus estados (etapa y dueño) y su persistencia en catalog-api y su base de datos.
- Implementar en catalog-api la lógica de subida, listado o eliminación de imágenes.
- La frontera `/panel/catalog`, la publicación y el frontend del panel (panel-api y panel-web).
- Aprovisionar MinIO (StatefulSet y servicio ya existen) y modificar la NetworkPolicy `platform-ingress` (ya permite el puerto 9000).
- Definir el valor concreto de las credenciales ni el policy JSON de MinIO más allá de su alcance al bucket.

## Criterios de finalización

- Todos los RF verificables en Minikube: existe el bucket `product-images`, los objetos de MinIO quedan en la ruta local reservada, catalog-api recibe las cuatro variables S3 con credenciales dedicadas y panel-api recibe `CATALOG_API_BASE_URL`.
- En Hostinger, el PVC de MinIO conserva las imágenes y las credenciales dedicadas llegan por secret cifrado, sin texto claro en el repositorio.
- `docs/product-images.md` describe la ruta local, el bucket, la política y las credenciales manuales.
- Comprobado que las credenciales de imágenes no aparecen en claro en el repositorio.
- `make validate` termina en verde tras los cambios de manifiestos.

## Dudas abiertas

Ninguna.
