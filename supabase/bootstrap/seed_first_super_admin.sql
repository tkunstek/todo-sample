\set ON_ERROR_STOP on

WITH ins_org AS (
  INSERT INTO public.organizations (name)
  SELECT :'first_org_name'
  WHERE NOT EXISTS (SELECT 1 FROM public.organizations WHERE name = :'first_org_name')
  RETURNING id
),
org AS (
  SELECT id FROM ins_org
  UNION ALL
  SELECT id FROM public.organizations WHERE name = :'first_org_name'
  LIMIT 1
)
INSERT INTO public.profiles (id, org_id, role, is_super_admin)
SELECT :'super_admin_uid'::uuid, (SELECT id FROM org), 'org_admin', true
ON CONFLICT (id) DO NOTHING;
