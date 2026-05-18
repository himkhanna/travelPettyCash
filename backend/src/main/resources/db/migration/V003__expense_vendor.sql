-- Add vendor name to expense rows (free-text, optional). See CLAUDE.md §5.
ALTER TABLE expense ADD COLUMN vendor varchar(200);
