-- Migration 002 (console): Stories backlog (build-ready work)
--
-- `stories` is the committed backlog — well-formed, actionable work items, in
-- contrast to `ideas` (raw scratchpad, migration 001). An idea is *promoted* into
-- a story: the story records stories.source_idea_id, and the idea's status flips to
-- 'promoted' so it leaves the raw idea list. Stories may also be born directly
-- (source_idea_id NULL). Admin tooling, owned by the Console surface; gated to
-- editor/admin in the Flutter UI, same RLS model as ideas.

CREATE TABLE IF NOT EXISTS stories (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_name       text NOT NULL,                    -- surface/pillar: pibrief|console|qbank|platform
  title          text NOT NULL,                    -- concise, imperative ("Add missing-qno panel")
  description    text,                             -- the well-formed body / context / approach
  acceptance     jsonb NOT NULL DEFAULT '[]'::jsonb,   -- checklist: [{ "text": "...", "done": false }]
  kind           text NOT NULL DEFAULT 'feature'
                   CHECK (kind IN ('feature','bug','chore','refactor','spike','design')),
  priority       text NOT NULL DEFAULT 'medium'
                   CHECK (priority IN ('low','medium','high','urgent')),
  status         text NOT NULL DEFAULT 'backlog'
                   CHECK (status IN ('backlog','ready','in_progress','blocked','in_review','done','dropped')),
  size           text CHECK (size IN ('xs','s','m','l','xl')),   -- rough estimate, nullable
  rank           double precision NOT NULL DEFAULT 0,            -- manual ordering (float = insert-between)
  labels         text[] NOT NULL DEFAULT '{}',
  source_idea_id uuid REFERENCES ideas(id) ON DELETE SET NULL,   -- promoted-from link (nullable)
  external_ref   text,                             -- GitHub issue/PR URL, optional
  started_at     timestamptz,                      -- set when -> in_progress (cycle time)
  completed_at   timestamptz,                      -- set when -> done
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS stories_status_rank_idx ON stories (status, rank);
CREATE INDEX IF NOT EXISTS stories_app_idx ON stories (app_name);

-- Reuse the shared updated_at trigger fn (defined in migration 001).
DROP TRIGGER IF EXISTS stories_updated_at ON stories;
CREATE TRIGGER stories_updated_at
  BEFORE UPDATE ON stories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS: same model as ideas — authenticated full access, gated to editor/admin in UI.
ALTER TABLE stories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated full access" ON stories;
CREATE POLICY "authenticated full access"
  ON stories FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.stories TO authenticated;

-- Promotion: an idea that becomes a story is marked 'promoted' so it drops out of
-- the active idea list. Widen the existing ideas.status CHECK to allow it.
ALTER TABLE ideas DROP CONSTRAINT IF EXISTS ideas_status_check;
ALTER TABLE ideas ADD CONSTRAINT ideas_status_check
  CHECK (status IN ('open','in_progress','done','dropped','promoted'));
