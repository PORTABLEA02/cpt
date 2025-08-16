/*
  # Schéma principal Perfecto Comptabilité

  1. Entités principales
    - `companies` - Sociétés
    - `fiscal_years` - Exercices comptables
    - `accounting_frameworks` - Cadres comptables (OHADA, Bancaire, etc.)
    - `sites` - Sites comptables autonomes
    - `currencies` - Devises
    - `users_permissions` - Permissions utilisateurs

  2. Sécurité
    - RLS activé sur toutes les tables
    - Politiques par société et utilisateur
    - Contrôles d'accès granulaires
*/

-- Cadres comptables (OHADA, Bancaire, Assurances, etc.)
CREATE TABLE IF NOT EXISTS accounting_frameworks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  country text DEFAULT '',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Devises
CREATE TABLE IF NOT EXISTS currencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL, -- 3 caractères (EUR, XOF, USD, etc.)
  name text NOT NULL,
  symbol text DEFAULT '',
  last_rate numeric(15,6) DEFAULT 1,
  is_base boolean DEFAULT false, -- Devise de base
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Sociétés
CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  address text DEFAULT '',
  phone text DEFAULT '',
  email text DEFAULT '',
  accounting_framework_id uuid REFERENCES accounting_frameworks(id),
  base_currency_id uuid REFERENCES currencies(id),
  country text DEFAULT '',
  tax_number text DEFAULT '',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Exercices comptables
CREATE TABLE IF NOT EXISTS fiscal_years (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code text NOT NULL, -- AA (2 derniers chiffres année)
  start_date date NOT NULL,
  end_date date NOT NULL,
  extended_end_date date, -- Pour prolongation
  is_closed boolean DEFAULT false,
  closure_date date,
  result_calculated boolean DEFAULT false,
  result_calculation_date date,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, code)
);

-- Sites comptables autonomes
CREATE TABLE IF NOT EXISTS sites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, code)
);

-- Natures analytiques (centres de coûts, activités, financements, etc.)
CREATE TABLE IF NOT EXISTS analytical_natures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('cost_center', 'activity', 'financing', 'budget_nomenclature', 'misc_analysis')),
  description text DEFAULT '',
  requires_input boolean DEFAULT true,
  allows_carryforward boolean DEFAULT false, -- Report des soldes
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, code)
);

-- Codes analytiques (centres, activités, financements, etc.)
CREATE TABLE IF NOT EXISTS analytical_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  analytical_nature_id uuid NOT NULL REFERENCES analytical_natures(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  parent_code text DEFAULT '', -- Pour regroupements
  is_group boolean DEFAULT false,
  currency_id uuid REFERENCES currencies(id), -- Pour financements
  default_activity text DEFAULT '', -- Activité par défaut pour centres
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, analytical_nature_id, code)
);

-- Permissions utilisateurs détaillées
CREATE TABLE IF NOT EXISTS user_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid REFERENCES fiscal_years(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('administrator', 'director', 'operator')),
  
  -- Droits généraux
  can_modify_parameters boolean DEFAULT false,
  can_create_definitions boolean DEFAULT false,
  can_modify_definitions boolean DEFAULT false,
  can_delete_definitions boolean DEFAULT false,
  
  -- Droits de saisie
  allowed_journals text DEFAULT '*', -- Codes des journaux autorisés
  allowed_accounts text DEFAULT '*', -- Comptes autorisés
  entry_restriction text DEFAULT 'all' CHECK (entry_restriction IN ('all', 'last_entry_only')),
  
  -- Droits spécifiques
  can_manage_contracts boolean DEFAULT false,
  can_validate_contracts boolean DEFAULT false,
  can_modify_payments boolean DEFAULT false,
  can_modify_budgets boolean DEFAULT false,
  can_periodic_closure boolean DEFAULT false,
  can_calculate_result boolean DEFAULT false,
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, company_id, fiscal_year_id)
);

-- RLS
ALTER TABLE accounting_frameworks ENABLE ROW LEVEL SECURITY;
ALTER TABLE currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytical_natures ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytical_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;

-- Politiques RLS
CREATE POLICY "Users can read accounting frameworks"
  ON accounting_frameworks FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can read currencies"
  ON currencies FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can access their companies"
  ON companies FOR ALL
  TO authenticated
  USING (
    id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their fiscal years"
  ON fiscal_years FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their sites"
  ON sites FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their analytical structures"
  ON analytical_natures FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their analytical codes"
  ON analytical_codes FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can read their permissions"
  ON user_permissions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Administrators can manage permissions"
  ON user_permissions FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_permissions up 
      WHERE up.user_id = auth.uid() 
      AND up.role = 'administrator'
      AND up.company_id = company_id
      AND up.is_active = true
    )
  );