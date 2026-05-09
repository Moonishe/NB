-- ============================================
-- FIX: Restore UTF-8 Cyrillic text in Supabase
-- Run this in Supabase SQL Editor
-- ============================================

-- Forum categories
UPDATE forum_categories SET name = 'Обсуждение', description = 'Общее обсуждение проекта NeuroBench' WHERE slug = 'discussion';
UPDATE forum_categories SET name = 'ИИ и генерация', description = 'Обсуждение ИИ моделей, генерации и бенчмарков' WHERE slug = 'ai-generation';
UPDATE forum_categories SET name = 'Оффтоп', description = 'Общение на свободные темы' WHERE slug = 'offtopic';

-- Verify
SELECT id, slug, name, description FROM forum_categories ORDER BY sort_order;
