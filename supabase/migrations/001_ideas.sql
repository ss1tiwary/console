-- Migration 001 (console): Ideas board (admin scratchpad)
--
-- Moved here from pibrief (was pibrief migration 013) — ideas is admin tooling,
-- owned by the Console surface, not the PIBrief content pillar. The table already
-- exists in the shared Supabase project; this file is the canonical, console-owned
-- definition. Do not re-run against a DB that already has `ideas`.
--
-- A simple global scratchpad for logging raw app ideas. Not tied to any user;
-- gated to editor/admin in the Console UI. Well-formed work lives in `stories`
-- (migration 002); an idea is promoted into a story via stories.source_idea_id.

CREATE TABLE IF NOT EXISTS ideas (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_name     text NOT NULL,                        -- e.g. 'pibrief', 'console', 'qbank'
  title        text NOT NULL,
  body         text,
  category     text CHECK (category IN ('feature','bug','content','design','data','other')),
  priority     text CHECK (priority IN ('low','medium','high')) DEFAULT 'medium',
  status       text CHECK (status IN ('open','in_progress','done','dropped')) DEFAULT 'open',
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Shared trigger fn to keep updated_at fresh (reused by stories).
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS ideas_updated_at ON ideas;
CREATE TRIGGER ideas_updated_at
  BEFORE UPDATE ON ideas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS: authenticated users have full access (page is gated to admin/editor in Flutter UI)
ALTER TABLE ideas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated full access" ON ideas;
CREATE POLICY "authenticated full access"
  ON ideas FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Table-level grant (RLS policy alone is not enough in Postgres)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ideas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ideas TO service_role;
