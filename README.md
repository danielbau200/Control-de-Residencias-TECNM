# Sistema de Control de Residencias Profesionales — Ingeniería Industrial (TecNM)

Aplicación web interna con respaldo en **PostgreSQL 16** diseñada para la oficina encargada de recibir y dar seguimiento a las solicitudes impresas de **Residencias Profesionales** de Ingeniería Industrial.

El sistema opera con **2 perfiles administrativos activos** (los estudiantes no tienen cuenta; realizan su entrega presencial y reciben avisos en su correo institucional):
- **Usuario 1 · Gestión (`GESTION_1`)**: Recepción de hojas impresas, captura de solicitudes y correo institucional, seguimiento de Servicio Social y trámites pausados, emisión de Oficios de Autorización (`P.A`) y Asignación de Asesor (`P.B`), impresión y envío de avisos por **Microsoft Outlook**.
- **Usuario 2 · Academia (`ACADEMIA`)**: Revisión técnica de anteproyectos, consulta de carga en tiempo real de la plantilla de **42 docentes** y asignación de **Asesor Interno** con folio de control (`26-1-X`), además de consultas, exportación a Excel (`CSV`) y bitácora.

---

## ¿Qué problemas resuelve?

1. **Adiós al control disperso en archivos de Excel**: Centraliza todos los expedientes físicos en formularios guiados, búsqueda multicampo instantánea (`⌘K` / `Ctrl+K`), filtros combinados y exportación a Excel (`CSV`).
2. **Control de Servicio Social y proyectos pausados**: La oficina recibe solicitudes impresas sin poder consultar previamente si el alumno liberó su Servicio Social; el sistema permite detener o apartar ordenadamente los trámites **Pausados** o **Detenidos por Servicio Social** sin perder su historial y reactivarlos cuando acrediten el requisito.
3. **Asignación equitativa entre 42 docentes**: Ordena automáticamente a los profesores de menor a mayor carga actual y muestra su jornada (`40 hrs`, `30 hrs`, `20 hrs`, `Por horas`) y beca (`EDD`).
4. **Folios consecutivos sin duplicados**: Genera de forma atómica los folios `P.A` y `P.B` en PostgreSQL mediante bloqueos transaccionales (`pg_advisory_xact_lock`), además de ofrecer vista previa lista para imprimir/PDF.
5. **Avisos por correo institucional (Microsoft Outlook)**: Permite redactar y abrir el correo en **Outlook Web** en 1 clic con todos los datos del expediente prellenados (o enviar directamente vía **SMTP Office 365**), registrando fecha, destinatario y medio en la bitácora.
6. **Seguridad y auditoría en base de datos**:
   - Rol restringido `app_residencias_user` sin acceso directo a tablas (`REVOKE ALL ON ALL TABLES`).
   - Toda escritura pasa por Procedimientos Almacenados `SECURITY DEFINER` con validación de rol activo (`RBAC`).
   - Consultas 100% parametrizadas sobre `libpq` (`PQexecParams`) sin concatenación SQL.
   - Registro automático de movimientos y cambios de estado en `bitacora_movimientos`.

---

## Estructura del repositorio

```text
├── README.md                                  # Documentación del proyecto
├── .env.example                               # Plantilla de variables de entorno (sin secretos)
├── .gitignore                                 # Exclusión de .env, cachés, backups y archivos locales
├── abrir-sistema.sh                           # Script de arranque (PostgreSQL 16 + Flask + navegador)
├── index.html                                 # Redirección a la vista principal del sistema
├── residencias_industrial_db.sql              # Esquema base, tablas, catálogo docente y datos iniciales
├── sql/
│   ├── 02_procedimientos_y_seguridad.sql      # Rol mínimo privilegio, RBAC, funciones API y 7 SPs
│   └── 03_migracion_sin_sii_2usuarios_outlook.sql # Migración a 2 usuarios, sin SII y soporte Outlook
├── backend/
│   ├── pg_client.py                           # Cliente PostgreSQL parametrizado vía libpq (ctypes)
│   └── server.py                              # API REST Flask + servido estático + integración Outlook
├── fronted/
│   ├── pages/
│   │   └── gestion-vinculacion.html           # Interfaz principal estilo macOS (Usuario 1 y Usuario 2)
│   └── assets/
│       ├── css/app.css                        # Estilos macOS Light Vibrancy, tablas Finder e impresión
│       └── js/
│           ├── db-residencias.js              # Respaldo offline de expedientes físicos y 42 docentes
│           ├── store.js                       # Capa de datos (API PostgreSQL + respaldo localStorage)
│           ├── ui-components.js               # Badges, steppers, barras de carga y formato tipográfico
│           └── app.js                         # Controlador SPA, vistas, inspector lateral y modal Outlook
└── diagramas/
    ├── 1_CASOS_DE_USO_RESIDENCIAS.drawio      # Casos de uso (actores, módulos, include/extend y tabla)
    ├── 2_FLUJO_PROCESO_CLIENTE.drawio         # Flujo completo de ventanilla en lenguaje no técnico
    └── 3_ARQUITECTURA_SEGURIDAD_SECUENCIA.drawio # Diagrama UML de secuencia y capas de seguridad
```

---

## Requisitos y cómo ejecutarlo

### 1. Requisitos previos
- **Python 3.10+** con **Flask** (`pip install flask`).
- **PostgreSQL 16** instalado y en ejecución (incluyendo `libpq.so.5`).
- Opcional: **draw.io / diagrams.net** para abrir o editar los archivos `.drawio` en `diagramas/`.

### 2. Configurar variables de entorno
Copia `.env.example` a `.env` y define una contraseña segura (`.env` está en `.gitignore` y nunca debe subirse):

```bash
cp .env.example .env
```

Edita `.env`:
```env
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=residencias_industrial_db
PGUSER=app_residencias_user
PGPASSWORD=TU_PASSWORD_SEGURA

FLASK_HOST=::
FLASK_PORT=8000

# Opcional: solo si deseas envío directo SMTP sin abrir Outlook Web
OUTLOOK_EMAIL=
OUTLOOK_PASSWORD=
OUTLOOK_SMTP_HOST=smtp.office365.com
OUTLOOK_SMTP_PORT=587
```

### 3. Crear e inicializar la base de datos en PostgreSQL 16
Antes de ejecutar `sql/02_procedimientos_y_seguridad.sql`, reemplaza `'CAMBIAR_CONTRASENA_SEGURA'` dentro de ese archivo (o ejecuta un `ALTER ROLE app_residencias_user WITH PASSWORD '...'` posterior) con la misma contraseña que pusiste en `PGPASSWORD` dentro de `.env`:

```bash
createdb -h 127.0.0.1 -U postgres residencias_industrial_db
psql -h 127.0.0.1 -U postgres -d residencias_industrial_db -v ON_ERROR_STOP=1 -f residencias_industrial_db.sql
psql -h 127.0.0.1 -U postgres -d residencias_industrial_db -v ON_ERROR_STOP=1 -f sql/03_migracion_sin_sii_2usuarios_outlook.sql
psql -h 127.0.0.1 -U postgres -d residencias_industrial_db -v ON_ERROR_STOP=1 -f sql/02_procedimientos_y_seguridad.sql
```

### 4. Ejecutar el sistema
Con el script todo-en-uno:
```bash
chmod +x abrir-sistema.sh
./abrir-sistema.sh
```

O iniciando manualmente el backend Flask:
```bash
python3 backend/server.py
```

Luego abre en tu navegador:
- **Sistema Web:** `http://localhost:8000`
- **Verificación de estado API:** `http://localhost:8000/api/health`
