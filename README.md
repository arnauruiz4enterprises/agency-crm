# Agency CRM

CRM para la agencia y app para las modelos (Content Hub), en una sola web.

- **Admins** ven todo el CRM: Plan, Accounts, Pipeline, Content, Analytics, Variations, Inspo, plantillas, proyectos, tareas y accesos.
- **Modelos** solo ven su app: su contenido pendiente, las instrucciones, el botón "Hecho", sus propuestas y los tutoriales.

## Piezas

| Archivo | Qué es |
|---|---|
| `index.html` | La aplicación completa (CRM + app de modelos) |
| `config.js` | Conexión con Supabase (Project URL + anon key) |
| `supabase/schema.sql` | Tablas y reglas de acceso; se ejecuta una vez en Supabase |
| `vercel.json` | Ajustes de publicación en Vercel |

No hace falta compilar nada: Vercel publica los archivos tal cual.

## Puesta en marcha

1. En Supabase → SQL Editor, ejecuta `supabase/schema.sql`.
2. En Supabase → Authentication → URL Configuration, pon como *Site URL* la dirección de Vercel.
3. Rellena `config.js` con la Project URL y la anon key.
4. Importa el repositorio en Vercel (Add New → Project).
5. Abre la web y crea tu cuenta: **la primera cuenta registrada es admin**.
6. Las modelos crean su cuenta desde "Crear cuenta"; tú les asignas su creadora en **Model Allocation → Accesos**.

## Secciones y cómo se conectan

- **CD Interface** (Plan, Accounts, Pipeline, Content, Analytics, Variations, Inspo, Trial Reel Templates): el trabajo por creadora. Cada registro de `content` pasa por Template → To Do → Instructions Added → Recorded → Edited → Approved → Posted.
- **Posting** (colección `actions`): una tarea de publicación por cuenta y pieza. Cada tarea enlaza una cuenta (`account`) y una variación (`variation_id` + `variation`), y lleva su propio flujo: `status`, `reasoning`, `assignee`, `due`, `screenshots`. Pestañas por plataforma (Suspended, IG, YT, Twitter, TikTok, Threads). Es transversal a todas las creadoras.
  - **Funneling**: `Attribution Links` es una vista sobre `accounts` (GAML Landing, OF Tracking Link, qué falta). `Link Pages` (`linkpages`) y `Tracking Links` (`trackinglinks`) son colecciones propias. Las dos vistas que en Kalista son automáticas del scraper (Inactive GAML y OF Links With Clicks) no se incluyen porque las genera su rastreador, no se escriben a mano.
- **Edits MGMT**: vistas sobre `content` para los editores. Usa campos de edición del propio contenido: `editor`, `editing_priority`, `editing_time`, `edited_by`, `edited_date`, `edit_count`, `edited_variations_needed`. Editing agrupa por editor; Editor's Work muestra lo ya editado por fecha.

- **Knowledge Library** (`knowledge`): SOPs y documentos internos, agrupados por categoría. Cada documento tiene tipo, un link al documento (Drive/Notion) y notas.

Las colecciones `actions`, `linkpages`, `trackinglinks` y `knowledge` son solo de admin: las reglas de Supabase no dan a las modelos ningún acceso a ellas.

## Seguridad

La seguridad la dan las reglas de Supabase (RLS): una modelo solo puede leer su contenido y crear propuestas suyas, aunque manipule la web. Nunca pongas la clave `service_role` en este repositorio.
