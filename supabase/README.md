# Supabase schema

`migrations/202610270001_initial_schema.sql` defines the first server schema and
its row-level security policies. It is a source migration only; it has not been
applied to a Supabase project because this repository has no project reference
or credentials.

## Data ownership

- Every business row carries `workspace_id` and is visible only to a member of
  that workshop. Foreign keys include the workspace so a row cannot point at a
  client, vehicle, order, or product from another workshop.
- A signed-in user creates a workshop by inserting its name and their own
  `created_by` ID. A database trigger adds that user as the first owner.
- No client-side role can hard-delete business rows. The app uses soft deletion
  so future synchronization can preserve deletion markers.
- `products.stock_milli` is a server-managed projection. A stock movement
  trigger updates it in the same PostgreSQL transaction and rejects a movement
  that would make inventory negative. The client cannot directly insert or
  update that column.

## Before connecting the Flutter client

The current Drift tables do not yet have a `workspace_id`, authentication, or a
remote change-application service. Add those in a separate local migration,
then implement an authenticated sync worker that uploads stock movements before
acknowledging their queue entries and applies remote rows with the local
outbox-suppression API in `AppDatabase.applyRemoteChanges`.

Do not put a Supabase secret/service key in the Flutter app. Client requests
must use a publishable/anon key with a signed-in session and rely on the RLS
policies in the migration.
