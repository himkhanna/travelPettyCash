-- Add the two mock-OIDC test users as members of the seeded trip so the
-- demo can exercise expense + transfer flows when logged in via the
-- /auth/login endpoint. Without this they would always hit
-- NOT_TRIP_MEMBER on /trips/{id}/expenses.
INSERT INTO trip_member (trip_id, user_id) VALUES
    ('cccccccc-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555'),
    ('cccccccc-0000-0000-0000-000000000001', '66666666-6666-6666-6666-666666666666')
ON CONFLICT DO NOTHING;
