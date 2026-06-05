CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE users (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  created_at timestamptz NOT NULL
);

CREATE TABLE planned_blocks (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  title text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  source text NOT NULL,
  external_event_id text,
  updated_at timestamptz NOT NULL
);

CREATE TABLE reality_logs (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  planned_block_id uuid REFERENCES planned_blocks(id),
  user_text text NOT NULL,
  generated_summary text,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE daily_summaries (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  day text NOT NULL,
  summary text NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE embeddings (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  embedding vector(1536) NOT NULL,
  created_at timestamptz NOT NULL
);

CREATE INDEX embeddings_vector_idx ON embeddings USING hnsw (embedding vector_cosine_ops);
