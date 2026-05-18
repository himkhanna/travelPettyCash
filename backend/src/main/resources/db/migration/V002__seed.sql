-- Seed reference data + a sample active trip.
-- See CLAUDE.md §1, §5.

-- ---------------------------------------------------------------------------
-- USERS (the 4 roles from CLAUDE.md §1 + 2 mock-OIDC test users)
-- ---------------------------------------------------------------------------
INSERT INTO app_user (id, username, display_name, display_name_ar, email, role, is_active, created_at) VALUES
    ('11111111-1111-1111-1111-111111111111', 'member1',     'Khalid Al Mansoori',  'خالد المنصوري',  'member1@pdd.gov.ae',    'MEMBER',      TRUE, now()),
    ('22222222-2222-2222-2222-222222222222', 'leader1',     'Ahmed Al Suwaidi',    'أحمد السويدي',   'leader1@pdd.gov.ae',    'LEADER',      TRUE, now()),
    ('33333333-3333-3333-3333-333333333333', 'admin1',      'Fatima Al Hashimi',   'فاطمة الهاشمي',  'admin1@pdd.gov.ae',     'ADMIN',       TRUE, now()),
    ('44444444-4444-4444-4444-444444444444', 'superadmin1', 'Mohammed Al Falasi',  'محمد الفلاسي',   'dg@pdd.gov.ae',         'SUPER_ADMIN', TRUE, now()),
    ('55555555-5555-5555-5555-555555555555', 'uaepass-test','UAE Pass Test User',  'مستخدم تجريبي',  'uaepass-test@pdd.gov.ae','LEADER',     TRUE, now()),
    ('66666666-6666-6666-6666-666666666666', 'pddsso-test', 'PDD SSO Test Admin',  'مسؤول تجريبي',   'pddsso-test@pdd.gov.ae','ADMIN',       TRUE, now());

-- ---------------------------------------------------------------------------
-- FUNDING SOURCES (CLAUDE.md §1)
-- ---------------------------------------------------------------------------
INSERT INTO fund_source (id, name, name_ar, is_active) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'Zabeel Office',               'مكتب زعبيل',                       TRUE),
    ('aaaaaaaa-0000-0000-0000-000000000002', 'Ministry of External Affairs','وزارة الشؤون الخارجية / التشريفات', TRUE);

-- ---------------------------------------------------------------------------
-- EXPENSE CATEGORIES (CLAUDE.md §5 — 8 categories)
-- ---------------------------------------------------------------------------
INSERT INTO expense_category (id, code, name_en, name_ar, icon_key, is_active) VALUES
    ('bbbbbbbb-0000-0000-0000-000000000001', 'FOOD',          'Food',          'الطعام',         'cutlery',     TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000002', 'TRANSPORT',     'Transport',     'المواصلات',      'car',         TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000003', 'HOTEL',         'Hotel',         'الفندق',         'bed',         TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000004', 'PHONE',         'Phone',         'الهاتف',         'phone',       TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000005', 'ENTERTAINMENT', 'Entertainment', 'الترفيه',        'star',        TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000006', 'TIPS',          'Tips',          'البقشيش',        'coins',       TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000007', 'TRAVEL',        'Travel',        'السفر',          'plane',       TRUE),
    ('bbbbbbbb-0000-0000-0000-000000000008', 'OTHERS',        'Others',        'أخرى',           'tag',         TRUE);

-- ---------------------------------------------------------------------------
-- ONE ACTIVE TRIP (Riyadh, SAR; halalas = minor unit)
-- ---------------------------------------------------------------------------
INSERT INTO trip (
    id, name, country_code, country_name, currency, status, created_by, leader_id,
    total_budget_amount, total_budget_currency, image_url, created_at
) VALUES (
    'cccccccc-0000-0000-0000-000000000001',
    'Riyadh Delegation — May 2026',
    'SA',
    'Saudi Arabia',
    'SAR',
    'ACTIVE',
    '33333333-3333-3333-3333-333333333333',  -- admin1 created
    '22222222-2222-2222-2222-222222222222',  -- leader1
    5000000,  -- 50,000.00 SAR in halalas
    'SAR',
    NULL,
    now()
);

INSERT INTO trip_member (trip_id, user_id) VALUES
    ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111'),
    ('cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222'),
    ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333'),
    ('cccccccc-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444');
