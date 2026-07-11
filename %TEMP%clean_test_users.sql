DELETE FROM public.deliverers WHERE user_id IN (
  SELECT id FROM public.users WHERE auth_id IN (
    SELECT id FROM auth.users WHERE email IN (
      'deivyosoriorondon+gorider@gmail.com', 'dayrimb@gmail.com',
      'becembermontiel.12@gmail.com', 'jessicatovar472@gmail.com',
      'seronb.john@gmail.com', 'derian14de@gmail.com', 'derianosorio2@gmail.com'
    )
  )
);
DELETE FROM public.users WHERE auth_id IN (
  SELECT id FROM auth.users WHERE email IN (
    'deivyosoriorondon+gorider@gmail.com', 'dayrimb@gmail.com',
    'becembermontiel.12@gmail.com', 'jessicatovar472@gmail.com',
    'seronb.john@gmail.com', 'derian14de@gmail.com', 'derianosorio2@gmail.com'
  )
);
DELETE FROM auth.users WHERE email IN (
  'deivyosoriorondon+gorider@gmail.com', 'dayrimb@gmail.com',
  'becembermontiel.12@gmail.com', 'jessicatovar472@gmail.com',
  'seronb.john@gmail.com', 'derian14de@gmail.com', 'derianosorio2@gmail.com'
);
