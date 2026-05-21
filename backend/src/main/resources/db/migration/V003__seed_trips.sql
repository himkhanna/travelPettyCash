-- Trip + members + allocations + expenses, mirroring the Flutter DemoStore.

INSERT INTO trips (id, name, country_code, country_name, currency, status, created_by, leader_id, total_budget_minor, created_at, closed_at) VALUES
  ('trip-ksa-2026', 'KSA State Visit',  'SA', 'Saudi Arabia', 'SAR', 'ACTIVE', 'u-khalid', 'u-fatima', 9100000, '2026-04-28T09:00:00+04:00', NULL),
  ('trip-egy-2026', 'Cairo Delegation', 'EG', 'Egypt',        'EGP', 'ACTIVE', 'u-khalid', 'u-fatima', 4500000, '2026-05-02T10:30:00+04:00', NULL),
  ('trip-jor-2026', 'Amman Visit',      'JO', 'Jordan',       'JOD', 'CLOSED', 'u-khalid', 'u-fatima', 8500000, '2026-03-10T08:00:00+04:00', '2026-03-20T18:00:00+04:00');

INSERT INTO trip_members (trip_id, user_id) VALUES
  ('trip-ksa-2026', 'u-ahmed'),
  ('trip-ksa-2026', 'u-mohammed'),
  ('trip-ksa-2026', 'u-layla'),
  ('trip-egy-2026', 'u-ahmed'),
  ('trip-egy-2026', 'u-mohammed'),
  ('trip-jor-2026', 'u-ahmed'),
  ('trip-jor-2026', 'u-layla');

INSERT INTO allocations (id, trip_id, from_user_id, to_user_id, source_id, amount_minor, currency, status, created_at, responded_at) VALUES
  ('alloc-1', 'trip-ksa-2026', NULL,       'u-fatima',   'src-zabeel',   2500000, 'SAR', 'ACCEPTED', '2026-04-28T09:30:00+04:00', '2026-04-28T09:31:00+04:00'),
  ('alloc-2', 'trip-ksa-2026', NULL,       'u-fatima',   'src-protocol', 6600000, 'SAR', 'ACCEPTED', '2026-04-28T09:30:00+04:00', '2026-04-28T09:31:00+04:00'),
  ('alloc-3', 'trip-ksa-2026', 'u-fatima', 'u-ahmed',    'src-zabeel',    290000, 'SAR', 'ACCEPTED', '2026-04-29T08:00:00+04:00', '2026-04-29T08:15:00+04:00'),
  ('alloc-4', 'trip-ksa-2026', 'u-fatima', 'u-ahmed',    'src-protocol',  350000, 'SAR', 'ACCEPTED', '2026-04-29T08:00:00+04:00', '2026-04-29T08:15:00+04:00'),
  ('alloc-5', 'trip-ksa-2026', 'u-fatima', 'u-mohammed', 'src-zabeel',    290000, 'SAR', 'ACCEPTED', '2026-04-29T08:05:00+04:00', '2026-04-29T08:20:00+04:00'),
  ('alloc-6', 'trip-ksa-2026', 'u-fatima', 'u-mohammed', 'src-protocol',  350000, 'SAR', 'ACCEPTED', '2026-04-29T08:05:00+04:00', '2026-04-29T08:20:00+04:00'),
  ('alloc-7', 'trip-ksa-2026', 'u-fatima', 'u-layla',    'src-zabeel',    290000, 'SAR', 'PENDING',  '2026-05-12T14:00:00+04:00', NULL);

INSERT INTO expenses (id, trip_id, user_id, source_id, category_code, amount_minor, currency, quantity, details, occurred_at, receipt_object_key, created_at, updated_at) VALUES
  ('exp-1',  'trip-ksa-2026', 'u-ahmed',    'src-zabeel',   'HOTEL',         120000, 'SAR', 1, 'Hotel night — Burj Rafal',     '2026-04-29T22:00:00+04:00', 'demo/receipts/r1.jpg', '2026-04-29T22:05:00+04:00', '2026-04-29T22:05:00+04:00'),
  ('exp-2',  'trip-ksa-2026', 'u-ahmed',    'src-protocol', 'FOOD',           18000, 'SAR', 1, 'Lunch with delegation',        '2026-04-30T13:30:00+04:00', 'demo/receipts/r2.jpg', '2026-04-30T13:35:00+04:00', '2026-04-30T13:35:00+04:00'),
  ('exp-3',  'trip-ksa-2026', 'u-ahmed',    'src-zabeel',   'TRANSPORT',       7500, 'SAR', 1, 'Taxi to ministry',             '2026-04-30T09:00:00+04:00', NULL,                   '2026-04-30T09:10:00+04:00', '2026-04-30T09:10:00+04:00'),
  ('exp-4',  'trip-ksa-2026', 'u-ahmed',    'src-protocol', 'TIPS',            5000, 'SAR', 1, 'Bellhop',                      '2026-04-30T08:00:00+04:00', NULL,                   '2026-04-30T08:05:00+04:00', '2026-04-30T08:05:00+04:00'),
  ('exp-5',  'trip-ksa-2026', 'u-mohammed', 'src-zabeel',   'FOOD',           22500, 'SAR', 1, 'Dinner — Olive Garden Riyadh', '2026-04-30T21:00:00+04:00', 'demo/receipts/r3.jpg', '2026-04-30T21:05:00+04:00', '2026-04-30T21:05:00+04:00'),
  ('exp-6',  'trip-ksa-2026', 'u-mohammed', 'src-protocol', 'TRANSPORT',      35000, 'SAR', 1, 'Airport transfer',             '2026-04-28T17:30:00+04:00', NULL,                   '2026-04-28T17:35:00+04:00', '2026-04-28T17:35:00+04:00'),
  ('exp-7',  'trip-ksa-2026', 'u-mohammed', 'src-zabeel',   'PHONE',           9000, 'SAR', 1, 'Local SIM top-up',             '2026-04-29T11:00:00+04:00', NULL,                   '2026-04-29T11:05:00+04:00', '2026-04-29T11:05:00+04:00'),
  ('exp-8',  'trip-ksa-2026', 'u-fatima',   'src-protocol', 'HOTEL',         180000, 'SAR', 1, 'Hotel — Four Seasons',         '2026-04-29T22:00:00+04:00', 'demo/receipts/r4.jpg', '2026-04-29T22:05:00+04:00', '2026-04-29T22:05:00+04:00'),
  ('exp-9',  'trip-ksa-2026', 'u-fatima',   'src-zabeel',   'FOOD',           45000, 'SAR', 1, 'Group dinner',                 '2026-04-30T20:00:00+04:00', NULL,                   '2026-04-30T20:05:00+04:00', '2026-04-30T20:05:00+04:00'),
  ('exp-10', 'trip-ksa-2026', 'u-fatima',   'src-protocol', 'ENTERTAINMENT',  30000, 'SAR', 1, 'Cultural visit tickets',       '2026-05-01T15:00:00+04:00', NULL,                   '2026-05-01T15:05:00+04:00', '2026-05-01T15:05:00+04:00'),
  ('exp-11', 'trip-ksa-2026', 'u-ahmed',    'src-zabeel',   'FOOD',           14500, 'SAR', 1, 'Breakfast',                    '2026-05-01T08:00:00+04:00', NULL,                   '2026-05-01T08:05:00+04:00', '2026-05-01T08:05:00+04:00'),
  ('exp-12', 'trip-ksa-2026', 'u-ahmed',    'src-protocol', 'TRANSPORT',       6000, 'SAR', 1, 'Taxi',                         '2026-05-01T10:00:00+04:00', NULL,                   '2026-05-01T10:05:00+04:00', '2026-05-01T10:05:00+04:00'),
  ('exp-13', 'trip-ksa-2026', 'u-mohammed', 'src-protocol', 'OTHERS',         12000, 'SAR', 1, 'Stationery — meeting prep',    '2026-05-01T11:00:00+04:00', NULL,                   '2026-05-01T11:05:00+04:00', '2026-05-01T11:05:00+04:00'),
  ('exp-14', 'trip-ksa-2026', 'u-ahmed',    'src-zabeel',   'TIPS',            3000, 'SAR', 1, 'Driver',                       '2026-05-02T19:00:00+04:00', NULL,                   '2026-05-02T19:05:00+04:00', '2026-05-02T19:05:00+04:00'),
  ('exp-15', 'trip-ksa-2026', 'u-mohammed', 'src-zabeel',   'FOOD',           26000, 'SAR', 1, 'Lunch',                        '2026-05-02T13:00:00+04:00', NULL,                   '2026-05-02T13:05:00+04:00', '2026-05-02T13:05:00+04:00'),
  ('exp-16', 'trip-egy-2026', 'u-ahmed',    'src-protocol', 'HOTEL',         350000, 'EGP', 1, 'Hotel — Marriott Cairo',       '2026-05-03T22:00:00+04:00', 'demo/receipts/r5.jpg', '2026-05-03T22:05:00+04:00', '2026-05-03T22:05:00+04:00'),
  ('exp-17', 'trip-egy-2026', 'u-ahmed',    'src-zabeel',   'TRANSPORT',      75000, 'EGP', 1, 'Driver — daily',               '2026-05-04T08:00:00+04:00', NULL,                   '2026-05-04T08:05:00+04:00', '2026-05-04T08:05:00+04:00'),
  ('exp-18', 'trip-egy-2026', 'u-mohammed', 'src-protocol', 'FOOD',           42000, 'EGP', 1, 'Welcome dinner',               '2026-05-04T20:00:00+04:00', NULL,                   '2026-05-04T20:05:00+04:00', '2026-05-04T20:05:00+04:00'),
  ('exp-19', 'trip-jor-2026', 'u-ahmed',    'src-zabeel',   'HOTEL',          90000, 'JOD', 3, 'Hotel — 3 nights',             '2026-03-12T22:00:00+04:00', NULL,                   '2026-03-12T22:05:00+04:00', '2026-03-12T22:05:00+04:00'),
  ('exp-20', 'trip-jor-2026', 'u-layla',    'src-protocol', 'FOOD',           28000, 'JOD', 1, 'Group lunch',                  '2026-03-13T13:00:00+04:00', NULL,                   '2026-03-13T13:05:00+04:00', '2026-03-13T13:05:00+04:00');
