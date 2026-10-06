# CONALEP Objetos Perdidos

## Publicar en GitHub Pages

La aplicación conserva su estructura original: el frontend permanece en `web/` y el SQL de Supabase en `supabase/`.

El workflow `.github/workflows/pages.yml` publica **únicamente el contenido de `web/`** en GitHub Pages. No mueve ni modifica los archivos de la aplicación dentro del repositorio.

### 1. Sube el proyecto a GitHub

Crea un repositorio y sube estas carpetas/archivos:

- `web/`
- `supabase/`
- `.github/workflows/pages.yml`
- `README.md`

### 2. Configura los datos de Supabase como Secrets

En GitHub entra a:

`Settings > Secrets and variables > Actions > New repository secret`

Crea:

- `SUPABASE_URL` = URL de tu proyecto de Supabase
- `SUPABASE_ANON_KEY` = clave **anon/publishable** de Supabase

**No uses `service_role` ni ninguna clave secreta de servidor.**

El workflow genera `web/config.js` solo durante el despliegue, así que el repositorio puede conservar el `config.js` con los valores de ejemplo.

### 3. Activa GitHub Pages

En:

`Settings > Pages`

elige:

- **Source:** GitHub Actions

Después de hacer `push` a `main`, GitHub ejecutará el workflow y publicará la carpeta `web/`.

### 4. Configura Supabase

En Supabase > Authentication > URL Configuration, agrega como URL del sitio la dirección que te dé GitHub Pages, por ejemplo:

`https://TU-USUARIO.github.io/TU-REPOSITORIO/`

Si usas confirmación por correo, agrega también esa URL en los Redirect URLs correspondientes.

### 5. Importante sobre el funcionamiento

GitHub Pages solo aloja los archivos estáticos. La autenticación, base de datos, almacenamiento de imágenes y tiempo real siguen funcionando mediante Supabase.

La carpeta `supabase/` **no se publica como parte del sitio**. Sus archivos SQL se ejecutan en Supabase.

### Estructura conservada

```text
conalep-objetos-perdidos/
├── .github/
│   └── workflows/
│       └── pages.yml
├── web/
│   ├── index.html
│   ├── app.js
│   ├── config.js
│   ├── style.css
│   ├── sw.js
│   ├── manifest.json
│   ├── _headers
│   └── icons/
└── supabase/
    ├── 01_esquema.sql
    └── 02_mejoras.sql
```

`_headers` se conserva para otros hosts que lo soporten, aunque GitHub Pages no aplica ese formato de configuración. No se elimina porque forma parte de la configuración existente.

---

# CONALEP Objetos Perdidos: guía para publicarlo en internet

La app es una página web (PWA instalable). Los datos NO se guardan en el celular: viven en la nube (Supabase), así que todos ven lo mismo desde cualquier dispositivo.

```
supabase/01_esquema.sql   tablas, seguridad (RLS), imágenes, tiempo real
supabase/02_mejoras.sql   perfil automático, teléfono protegido, límite de publicaciones,
                          bloqueo de cuentas, bitácora automática, dominio de correo
web/                      la app (index.html, app.js, style.css, config.js, iconos, sw.js)
```

## Paso 1. Crear la base de datos (Supabase, gratis)
1. Entra a https://supabase.com, crea cuenta y pulsa **New project**. Elige nombre, contraseña de base de datos (guárdala) y región cercana.
2. Espera 1-2 minutos a que termine de crearse.

## Paso 2. Cargar el esquema
1. Menú **SQL Editor > New query**.
2. Pega TODO `supabase/01_esquema.sql` y pulsa **Run**. Debe decir "Success".
3. Nueva consulta: pega TODO `supabase/02_mejoras.sql` y **Run**.
   Si hay error, no sigas: copia el mensaje y revísalo antes de continuar.

## Paso 3. Conectar la app con tu proyecto
1. En Supabase: **Project Settings > API** (o "API Keys").
2. Copia **Project URL** y la clave **anon / publishable**.
3. Abre `web/config.js` y reemplaza `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
   Nunca uses la clave `service_role`: da control total y jamás debe estar en la web.

## Paso 4. Probar en tu computadora
En una terminal, dentro de la carpeta `web`:
```
python3 -m http.server 8000
```
Abre http://localhost:8000, regístrate y publica algo de prueba.

## Paso 5. Publicarla (elige UNA opción)

**Opción A: Netlify (la más fácil, 2 minutos)**
1. Entra a https://app.netlify.com/drop e inicia sesión.
2. Arrastra la carpeta **web** completa a la zona indicada.
3. Te da un enlace público tipo `https://nombre.netlify.app` (puedes cambiar el nombre en *Site configuration*).

**Opción B: GitHub Pages**
1. Crea un repositorio público en https://github.com/new.
2. Sube el CONTENIDO de la carpeta `web` a la raíz del repositorio (index.html debe quedar en la raíz).
3. **Settings > Pages > Source: Deploy from a branch > main / (root) > Save**.
4. En 1-2 minutos queda en `https://TU-USUARIO.github.io/NOMBRE-REPO/`.

**Opción C: Cloudflare Pages**
**Workers & Pages > Create > Pages > Upload assets**, sube la carpeta `web`.

## Paso 6. Decirle a Supabase cuál es tu enlace público
**Authentication > URL Configuration**:
- **Site URL**: tu enlace público (por ejemplo `https://nombre.netlify.app`).
- **Redirect URLs**: agrega el mismo enlace.
Sin esto, los correos de confirmación apuntan a localhost.

## Paso 7. Volverte administrador
Regístrate en la app y luego en **SQL Editor** ejecuta (con tu correo):
```sql
update profiles set rol='administrador' where email='tucorreo@ejemplo.com';
```

## Paso 8. Ajustes recomendados
- **Solo correos institucionales** (usa el dominio real):
  `update app_settings set dominio_permitido='conalep.edu.mx' where id=1;`
- **Confirmación de correo**: déjala activada en Authentication > Providers > Email.
  El correo gratuito de Supabase tiene límite de envíos por hora; para muchos alumnos configura tu propio SMTP en Authentication > SMTP Settings.
- **Suspender a un usuario** (como admin): `select suspender_usuario('ID-DEL-USUARIO', true);`
- **Ver la bitácora de moderación**: `select * from moderation_actions order by created_at desc;`

## Paso 9. Instalarla como app
- Android (Chrome): menú ⋮ > **Instalar app** / Agregar a pantalla de inicio.
- iPhone (Safari): Compartir > **Agregar a pantalla de inicio**.
El icono es el que mandaste.

## Lista de pruebas antes de abrirla a todos
1. Un alumno nuevo se registra y entra.
2. Publica con foto; se ve en otro dispositivo.
3. Su teléfono NO aparece hasta pulsar "Contactar".
4. Un segundo alumno no puede borrar ni editar la publicación del primero.
5. Una sexta publicación en 24 h es rechazada.
6. El admin borra una publicación ajena y aparece en `moderation_actions`.

## Problemas frecuentes
| Síntoma | Causa y solución |
|---|---|
| Pantalla en blanco | `config.js` sin tus datos, o abriste index.html con doble clic. Usa el Paso 4 o el enlace publicado. |
| "Database error saving new user" | Datos inválidos (matrícula, teléfono) o correo fuera del dominio permitido. |
| No llega el correo de confirmación | Revisa spam, el límite de envíos y el Paso 6. |
| "permission denied" | Falta correr `02_mejoras.sql` o se ejecutó en otro orden. |
| Cambié algo y no se actualiza | Recarga forzada (Ctrl+Shift+R) por la caché de la app instalada. |

## Funciones incluidas / pendientes
Incluido: registro e inicio de sesión, publicar con foto, búsqueda y filtros, reacciones, comentarios, estado de entrega, reportes, contacto protegido, borrado por admin con bitácora, tiempo real, instalable.
Pendiente (la base de datos ya lo soporta): pantallas de Preguntas y Respuestas y panel visual de moderación.
