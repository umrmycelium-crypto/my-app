CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS entities (
  entity_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  type text,
  visual_signature_id text,
  labels jsonb,
  attributes jsonb,
  source text,
  confidence numeric,
  last_seen timestamptz,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rules (
  rule_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  predicate text,
  conditions jsonb,
  evidence_clues jsonb,
  type text,
  version int DEFAULT 1,
  created_by text,
  created_at timestamptz DEFAULT NOW(),
  contradiction_count int DEFAULT 0,
  contradiction_threshold int DEFAULT 3,
  last_contradiction_at timestamptz,
  merged_from jsonb,
  status text DEFAULT 'active',
  confidence numeric DEFAULT 0.5
);

CREATE TABLE IF NOT EXISTS events (
  event_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  timestamp timestamptz DEFAULT NOW(),
  entity_id uuid REFERENCES entities(entity_id),
  detection jsonb,
  applied_rules jsonb,
  action text,
  user_feedback text
);

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);
CREATE INDEX IF NOT EXISTS idx_rules_status ON rules(status);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_entity ON events(entity_id);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO pgadmin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO pgadmin;

CREATE TABLE IF NOT EXISTS corrections (
  correction_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_id uuid REFERENCES entities(entity_id),
  rule_id uuid REFERENCES rules(rule_id),
  correction_type text,
  previous_value jsonb,
  corrected_value jsonb,
  reason text,
  corrected_by text,
  corrected_at timestamptz DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_corrections_entity ON corrections(entity_id);
