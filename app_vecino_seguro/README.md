# 🛡️ Vecino Seguro - Documentación de Configuración del Entorno

## 📌 Descripción del Proyecto
**Vecino Seguro** es una plataforma móvil orientada a la seguridad comunitaria. Este repositorio contiene la arquitectura base integrada por una aplicación móvil nativa en **Flutter**, una API REST backend en **Node.js (TypeScript)** y una base de datos relacional sobre **Docker**.

---

## 🛠️ Requisitos Previos

Antes de ejecutar el proyecto, asegúrate de tener instaladas las siguientes herramientas en tu sistema:

* **Flutter SDK:** v3.x o superior.
* **Dart SDK:** Incluido con Flutter.
* **Node.js:** v18.x o superior.
* **Docker Desktop:** Para la gestión de contenedores de la base de datos.
* **Android Studio & Android Emulator:** Con SDK de Android API 34/36 configurado.
* **VS Code / Editor de código:** Con extensiones de Flutter y Dart.

---

## ⚙️ Paso a Paso para la Configuración e Instalación

### 1. Clonar el Repositorio
```bash
git clone <URL_DE_TU_REPOSITORIO>
cd app_vecino_seguro
2. Configuración e Inicio de la Base de Datos (Docker)
Asegúrate de que Docker Desktop esté abierto y ejecutándose.

Inicia el contenedor de la base de datos PostgreSQL:

Bash
docker-compose up -d
La base de datos quedará escuchando en el puerto local por defecto.

3. Configuración y Ejecución del Backend (Node.js + Express)
Navega a la carpeta del servidor backend:

Bash
cd backend
Instala las dependencias del proyecto:

Bash
npm install
Crea un archivo .env en la raíz del backend con tus variables de entorno (ejemplo):

Fragmento de código
PORT=3333
DATABASE_URL=postgresql://usuario:password@localhost:5432/vecino_seguro
JWT_SECRET=tu_clave_secreta_jwt
Ejecuta el servidor en modo desarrollo:

Bash
npm run dev
(El servidor estará escuchando en http://localhost:3333)

4. Configuración y Ejecución del Frontend Móvil (Flutter)
Navega a la carpeta de la aplicación móvil:

Bash
cd app_vecino_seguro
Verifica la salud del entorno de desarrollo:

Bash
flutter doctor
Obtén las dependencias del proyecto:

Bash
flutter pub get
Autorización de tráfico HTTP en Android:
Asegúrate de que en android/app/src/main/AndroidManifest.xml esté habilitada la siguiente propiedad dentro de la etiqueta <application>:

XML
android:usesCleartextTraffic="true"
Abre el emulador de Android desde Android Studio o VS Code.

Ejecuta la aplicación móvil:

Bash
flutter run
📡 Puntos de Enlace de la API (Endpoints Principales)
Generar Token de Prueba: POST http://localhost:3333/api/usuarios/token-prueba

Acceso desde Emulador Android: Usar http://10.0.2.2:3333 en lugar de localhost.

👨‍💻 Autor
Estudiante: Jorge Luis Mendoza Mendoza

Asignatura: Aplicaciones Móviles

Institución: Universidad Estatal Amazónica (UEA)