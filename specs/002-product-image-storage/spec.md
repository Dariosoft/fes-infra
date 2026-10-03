# Spec 002 — Almacenamiento de imágenes de producto en MinIO y cableado

## Contexto y objetivo

Las imágenes de producto necesitan un almacenamiento compatible con S3 dentro del clúster. En Minikube, MinIO ya corre en el namespace `platform` (StatefulSet `minio`, servicio `minio.platform.svc.cluster.local:9000`) y la NetworkPolicy `platform-ingress` ya permite el puerto 9000 desde `apps`. Falta el bucket `product-images`, las credenciales dedicadas que usará catalog-api, un respaldo a demanda de los objetos en una carpeta local de Minikube, la URL pública con la que catalog-api arma las imágenes y la URL interna de catalog-api en panel-api. El bucket se crea de forma idempotente con un script del repositorio en Minikube; las credenciales y la carpeta local son configurables y quedan documentadas en `docs/product-images.md`, no asumidas por la generación de código.

El mismo corte habilita la depuración local de los APIs Java en Minikube (agente JDWP habilitado por `JAVA_DEBUG_OPTS`) para desarrollar el cableado S3 sin frenar el arranque normal; Hostinger no habilita el depurador.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- catalog-api, que consume el endpoint S3, el bucket, las credenciales dedicadas y la URL pública.
- panel-api, que consume la URL interna de catalog-api.
- MinIO, que almacena los objetos.
- Desarrollador que depura los APIs Java en Minikube y se adjunta con VS Code.

## Historias de usuario

- H1: Como operador quiero que exista el bucket `product-images` para que catalog-api guarde las imágenes de producto.
- H2: Como operador quiero que los objetos de MinIO se respalden automáticamente en una carpeta local al destruir el clúster y se restauren al desplegar, para no perder las imágenes al recrear el entorno.
- H3: Como catalog-api quiero recibir el endpoint, el bucket, las credenciales S3 y la URL pública del entorno para subir y servir imágenes sin configuración manual dentro del servicio.
- H4: Como panel-api quiero conocer la URL interna de catalog-api para reenviar las operaciones de catálogo.
- H5: Como operador quiero una guía con la configuración manual de la carpeta local, el bucket y las credenciales para reproducir el entorno sin adivinar valores.
- H6: Como desarrollador quiero adjuntar VS Code con JDWP a los APIs Java en Minikube para depurar el cableado S3 sin frenar el arranque normal.
- H7: Como operador quiero que Hostinger nunca exponga el depurador para no abrir puertos de depuración fuera del entorno local.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: EL SISTEMA dispondrá del bucket `product-images` para almacenar las imágenes de producto.
- RF-2: CUANDO se aprovisione el entorno Minikube, EL SISTEMA creará el bucket `product-images` de forma idempotente mediante un script del repositorio.
- RF-3: DONDE el entorno sea Minikube, EL SISTEMA respaldará a demanda los objetos del bucket `product-images` en la carpeta local `/Users/dariogutierrez/projects/friendly-e-shop/media/images`, manteniendo MinIO sobre su PVC.
- RF-4: SI la carpeta local no existe, ENTONCES EL SISTEMA la creará al respaldar, sin impedir el despliegue.
- RF-5: EL SISTEMA entregará a catalog-api la variable `S3_ENDPOINT` con la dirección del API S3 de MinIO del entorno (`http://minio.platform.svc.cluster.local:9000`).
- RF-6: EL SISTEMA entregará a catalog-api la variable `S3_BUCKET` con el valor `product-images`.
- RF-7: EL SISTEMA entregará a catalog-api la variable `S3_ACCESS_KEY` con la clave de acceso dedicada de las imágenes de producto.
- RF-8: EL SISTEMA entregará a catalog-api la variable `S3_SECRET_KEY` con la clave secreta dedicada de las imágenes de producto.
- RF-9: EL SISTEMA usará, para las imágenes de producto, credenciales dedicadas con una política limitada al bucket `product-images`, distintas de las credenciales raíz de MinIO.
- RF-10: EL SISTEMA entregará a panel-api la variable `CATALOG_API_BASE_URL` con el valor `http://catalog-api.apps.svc.cluster.local:8080`.
- RF-11: MIENTRAS el entorno esté desplegado, EL SISTEMA permitirá a los pods del namespace `apps` alcanzar el puerto 9000 de MinIO en el namespace `platform` mediante la política `platform-ingress`.
- RF-12: EL SISTEMA incluirá en `docs/product-images.md` la configuración manual de la carpeta local, el bucket y las credenciales.
- RF-13: SI faltan el bucket o las credenciales de imágenes en el entorno, ENTONCES EL SISTEMA no inventará valores y el operador deberá completarlos según `docs/product-images.md`.
- RF-14: CUANDO el operador ejecute el respaldo, EL SISTEMA copiará los objetos del bucket a la carpeta local; tras recrear Minikube, la restauración devolverá esos objetos al bucket.
- RF-15: DONDE el entorno sea Hostinger, EL SISTEMA respaldará las imágenes en el PVC de MinIO y entregará las credenciales dedicadas mediante un secret.
- RF-16: EL SISTEMA entregará a catalog-api la variable `PUBLIC_API_BASE_URL` con la URL pública del API por entorno (`https://api.friendly-e-shop.duckdns.org` en Minikube).
- RF-17: EL SISTEMA ofrecerá los comandos `make backup-images` y `make restore-images` para copiar los objetos del bucket a la carpeta local y viceversa.
- RF-18: DONDE el entorno sea Minikube, EL SISTEMA habilitará el agente JDWP en los APIs Java para que un depurador se adjunte a los pods.
- RF-19: EL SISTEMA asignará a cada API Java de Minikube un puerto JDWP distinto (`catalog-api` 5005, `account-api` 5006, `order-api` 5007, `payment-api` 5008).
- RF-20: EL SISTEMA hará que el agente JDWP escuche en `127.0.0.1` dentro del pod, de modo que solo sea alcanzable mediante port-forward.
- RF-21: DONDE el entorno sea Hostinger, EL SISTEMA no habilitará el agente JDWP.
- RF-22: CUANDO `JAVA_DEBUG_OPTS` esté definido, EL SISTEMA añadirá su valor a los argumentos de la JVM al recargar los APIs Java en Minikube.
- RF-23: SI `JAVA_DEBUG_OPTS` está vacío o ausente, ENTONCES EL SISTEMA arrancará el API sin exponer JDWP.
- RF-24: EL SISTEMA incluirá en `README.md` las instrucciones para adjuntar VS Code a los APIs Java de Minikube.
- RF-25: CUANDO el operador ejecute `make destroy` con el perfil de Minikube en ejecución, EL SISTEMA respaldará los objetos del bucket en la carpeta local antes de eliminar el clúster, sin bloquear el borrado si el respaldo falla o el perfil no está corriendo.
- RF-26: CUANDO el operador ejecute `make deploy`, EL SISTEMA restaurará en el bucket los objetos que falten desde la carpeta local, sin sobrescribir los que ya existan.

## Requisitos no funcionales

- La carpeta local de respaldo es específica de Minikube en macOS; ningún otro entorno debe depender de ella.
- Las credenciales de las imágenes de producto son configuración manual y no deben asumirse ni codificarse en la generación de código.
- Las credenciales de imágenes no deben quedar en claro en el repositorio ni en plantillas desplegables; en Hostinger viajan cifradas con SOPS.
- El aprovisionamiento del bucket debe ser idempotente: repetirlo no debe crear duplicados ni fallar.
- El aprovisionamiento debe seguir la estructura base/overlay del repositorio y no duplicar manifiestos completos entre Minikube y Hostinger.
- El depurador JDWP solo se habilita en Minikube y escucha en `127.0.0.1`; Hostinger nunca expone el depurador.

## Casos límite

- La carpeta local reservada no existe o está vacía: no debe impedir el despliegue; se crea al respaldar y el respaldo no contendrá imágenes todavía.
- El bucket `product-images` ya existe: el aprovisionamiento no debe crear un duplicado ni fallar.
- Las credenciales de imágenes no están definidas: catalog-api no dispondrá de `S3_ACCESS_KEY` ni `S3_SECRET_KEY` válidos y el despliegue no debe inventarlas.
- MinIO no está listo cuando arranca catalog-api: la indisponibilidad momentánea del API S3 no debe corromper datos.
- Recrear el clúster Minikube: los objetos se conservan solo si se respaldaron; `make destroy` respalda automáticamente (best-effort) y `make deploy` restaura los faltantes al recrear el entorno.
- Un entorno distinto de Minikube (Hostinger): las imágenes se respaldan en el PVC de MinIO y las credenciales dedicadas llegan por secret cifrado.
- `JAVA_DEBUG_OPTS` ausente o vacío: el API arranca normal y no expone JDWP.
- Entorno Hostinger: no se aplican los overlays de debug y el depurador queda deshabilitado.

## Fuera de alcance

- Definir el esquema de productos, sus estados (etapa y dueño) y su persistencia en catalog-api y su base de datos.
- Implementar en catalog-api la lógica de subida, listado o eliminación de imágenes.
- La frontera `/panel/catalog`, la publicación y el frontend del panel (panel-api y panel-web).
- Aprovisionar MinIO (StatefulSet y servicio ya existen) y modificar la NetworkPolicy `platform-ingress` (ya permite el puerto 9000).
- Definir el valor concreto de las credenciales ni el policy JSON de MinIO más allá de su alcance al bucket.
- Habilitar el depurador JDWP fuera de Minikube (Hostinger o producción).

## Criterios de finalización

- Todos los RF verificables en Minikube: existe el bucket `product-images`, `make backup-images` copia los objetos a la carpeta local y `make restore-images` los devuelve, catalog-api recibe las variables S3 y `PUBLIC_API_BASE_URL` con credenciales dedicadas y panel-api recibe `CATALOG_API_BASE_URL`.
- En Hostinger, el PVC de MinIO conserva las imágenes y las credenciales dedicadas llegan por secret cifrado, sin texto claro en el repositorio.
- `docs/product-images.md` describe la carpeta local, el bucket, la política y las credenciales manuales.
- En Minikube, `JAVA_DEBUG_OPTS` habilita JDWP en los cuatro APIs Java con puertos únicos y VS Code se adjunta por port-forward; Hostinger no habilita el depurador.
- Comprobado que las credenciales de imágenes no aparecen en claro en el repositorio.
- `make validate` termina en verde tras los cambios de manifiestos.

## Dudas abiertas

Ninguna.
