-- Seed mirroring the Flutter DemoStore so the swap is invisible to the user.

INSERT INTO users (id, username, display_name, display_name_ar, email, role) VALUES
  ('u-ahmed',  'ahmed.maktoum',  'Ahmed Al Maktoum',  'أحمد آل مكتوم',  'ahmed.maktoum@pdd.gov.ae',  'MEMBER'),
  ('u-fatima', 'fatima.hashimi', 'Fatima Al Hashimi', 'فاطمة الهاشمي',  'fatima.hashimi@pdd.gov.ae', 'LEADER'),
  ('u-mohammed','mohammed.ali',  'Mohammed Ali',      'محمد علي',       'mohammed.ali@pdd.gov.ae',   'MEMBER'),
  ('u-layla',  'layla.mansouri', 'Layla Al Mansouri', 'ليلى المنصوري',  'layla.mansouri@pdd.gov.ae', 'MEMBER'),
  ('u-khalid', 'khalid.suwaidi', 'Khalid Al Suwaidi', 'خالد السويدي',   'khalid.suwaidi@pdd.gov.ae', 'ADMIN'),
  ('u-noura',  'noura.falasi',   'Noura Al Falasi',   'نورة الفلاسي',   'noura.falasi@pdd.gov.ae',   'SUPER_ADMIN');

INSERT INTO sources (id, name, name_ar) VALUES
  ('src-zabeel',   'Zabeel Office',       'قصر زعبيل'),
  ('src-protocol', 'Protocol Department', 'دائرة التشريفات');

INSERT INTO expense_categories (id, code, name_en, name_ar, icon_key) VALUES
  ('cat-food',          'FOOD',          'Food',          'طعام',       'cutlery'),
  ('cat-transport',     'TRANSPORT',     'Transport',     'نقل',        'car'),
  ('cat-hotel',         'HOTEL',         'Hotel',         'فندق',       'bed'),
  ('cat-phone',         'PHONE',         'Phone',         'هاتف',       'phone'),
  ('cat-entertainment', 'ENTERTAINMENT', 'Entertainment', 'ترفيه',      'ticket'),
  ('cat-tips',          'TIPS',          'Tips',          'إكراميات',   'coin'),
  ('cat-travel',        'TRAVEL',        'Travel',        'سفر',        'plane'),
  ('cat-others',        'OTHERS',        'Others',        'أخرى',       'dots');
