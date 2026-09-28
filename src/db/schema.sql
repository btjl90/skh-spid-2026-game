-- Healthcare Sim Database Schema
-- PostgreSQL 15+

-- Scenes table
CREATE TABLE IF NOT EXISTS scenes (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    subtitle VARCHAR(255),
    description TEXT,
    image_url VARCHAR(500),
    image_description VARCHAR(500),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Questions table
CREATE TABLE IF NOT EXISTS questions (
    id VARCHAR(50) PRIMARY KEY,
    scene_id INTEGER REFERENCES scenes(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    option_a VARCHAR(500) NOT NULL,
    option_b VARCHAR(500) NOT NULL,
    option_c VARCHAR(500) NOT NULL,
    option_d VARCHAR(500) NOT NULL,
    correct_answer CHAR(1) NOT NULL DEFAULT 'a',
    explanation TEXT,
    image_url VARCHAR(500),
    image_description VARCHAR(500),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Scores table for session persistence
CREATE TABLE IF NOT EXISTS scores (
    session_id VARCHAR(100) PRIMARY KEY,
    total_score INTEGER NOT NULL DEFAULT 0,
    max_score INTEGER NOT NULL DEFAULT 0,
    scene_scores TEXT,  -- JSON string of scene_id -> score
    completed_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_questions_scene_id ON questions(scene_id);
CREATE INDEX IF NOT EXISTS idx_scores_completed_at ON scores(completed_at);

-- Sample data (optional - uncomment to seed)
-- INSERT INTO scenes (id, title, subtitle, description) VALUES
-- (1, 'Wound Assessment', 'Clinical Wound Assessment Simulation', 'You are a nurse completing a wound assessment...'),
-- (2, 'Pressure Injury Prevention', 'Risk Assessment and Prevention Strategies', 'You are a nurse performing a Braden Scale assessment...');
