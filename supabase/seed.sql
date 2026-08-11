-- Development-only prompt data. Production prompt content will be managed
-- through migrations/imports and the protected admin interface.
insert into public.prompts (prompt_text, level, category_id)
values
  ('What is something small that made you smile this week?', 1, 'secular'),
  ('What is a hobby you would love to try with friends?', 1, 'secular'),
  ('What is one thing you are thankful to God for today?', 1, 'christian'),
  ('What experience has shaped one of your important values?', 2, 'secular'),
  ('What has God been teaching you in this season?', 2, 'christian'),
  ('Where have you noticed faith affecting an everyday decision?', 2, 'hybrid'),
  ('What hope are you carrying that you rarely say aloud?', 3, 'secular'),
  ('Where would prayerful support feel most meaningful right now?', 3, 'christian'),
  ('What part of your identity are you learning to receive with grace?', 3, 'hybrid');
