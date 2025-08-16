/*
  # Structure des comptes et tiers

  1. Tables principales
    - `account_natures` - Natures des comptes
    - `general_accounts` - Comptes généraux
    - `thirds` - Tiers (fournisseurs, clients, personnel, etc.)
    - `auxiliary_accounts` - Comptes auxiliaires des tiers
    - `account_tracking` - Suivi des comptes (lettrable, pointable, etc.)

  2. Configuration
    - Comptes liés aux immobilisations
    - Comptes de suivi des marchés
    - Imputations automatiques
*/

-- Natures des comptes (prédéfinies par cadre comptable)
CREATE TABLE IF NOT EXISTS account_natures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  accounting_framework_id uuid NOT NULL REFERENCES accounting_frameworks(id),
  code text NOT NULL,
  name text NOT NULL,
  category text NOT NULL CHECK (category IN (
    'assets', 'liabilities', 'equity', 'income', 'expenses',
    'suppliers', 'customers', 'personnel', 'misc_third_parties',
    'fixed_assets', 'depreciation'
  )),
  is_supplier boolean DEFAULT false,
  is_customer boolean DEFAULT false,
  is_personnel boolean DEFAULT false,
  is_misc_third boolean DEFAULT false,
  is_fixed_asset boolean DEFAULT false,
  is_vat_collectible boolean DEFAULT false,
  is_vat_deductible boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(accounting_framework_id, code)
);

-- Comptes généraux
CREATE TABLE IF NOT EXISTS general_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  code text NOT NULL,
  name text NOT NULL,
  parent_code text DEFAULT '', -- Pour comptes de regroupement
  is_group boolean DEFAULT false,
  is_collective boolean DEFAULT false, -- Compte collectif de tiers
  is_individual boolean DEFAULT true, -- Compte individuel (peut recevoir écritures)
  
  -- Nature et configuration
  account_nature_id uuid REFERENCES account_natures(id),
  currency_id uuid REFERENCES currencies(id),
  bank_account_number text DEFAULT '',
  vat_rate numeric(5,2) DEFAULT 0,
  
  -- États et contrôles
  is_closed boolean DEFAULT false,
  closure_date date,
  is_active boolean DEFAULT true,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, COALESCE(site_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
);

-- Tiers (fournisseurs, clients, personnel, tiers divers)
CREATE TABLE IF NOT EXISTS thirds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('supplier', 'customer', 'personnel', 'misc')),
  parent_code text DEFAULT '', -- Pour regroupements
  is_group boolean DEFAULT false,
  
  -- Informations générales
  address text DEFAULT '',
  postal_code text DEFAULT '',
  city text DEFAULT '',
  country text DEFAULT '',
  phone text DEFAULT '',
  email text DEFAULT '',
  contact_person text DEFAULT '',
  
  -- Informations fiscales et bancaires
  tax_number text DEFAULT '', -- Pour fournisseurs
  responsibility_center text DEFAULT '', -- Pour personnel
  
  -- Configuration de paiement (fournisseurs)
  payment_delay_days integer DEFAULT 0,
  payment_min_day_week integer DEFAULT 1, -- Lundi = 1
  payment_min_day_month integer DEFAULT 1,
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, code)
);

-- Comptes auxiliaires (automatiquement générés)
CREATE TABLE IF NOT EXISTS auxiliary_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  general_account_id uuid NOT NULL REFERENCES general_accounts(id) ON DELETE CASCADE,
  third_id uuid NOT NULL REFERENCES thirds(id) ON DELETE CASCADE,
  
  code text NOT NULL, -- Code du compte général + code tiers
  name text NOT NULL,
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(general_account_id, third_id)
);

-- Configuration de suivi des comptes
CREATE TABLE IF NOT EXISTS account_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  account_code text NOT NULL, -- Peut utiliser wildcards
  tracking_type text NOT NULL CHECK (tracking_type IN (
    'letterable', 'pointable', 'payable', 'receivable'
  )),
  
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, account_code, tracking_type)
);

-- Imputations automatiques
CREATE TABLE IF NOT EXISTS automatic_imputations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  general_account_id uuid NOT NULL REFERENCES general_accounts(id) ON DELETE CASCADE,
  analytical_nature_id uuid NOT NULL REFERENCES analytical_natures(id),
  analytical_code text NOT NULL,
  percentage numeric(5,2) DEFAULT 100,
  
  created_at timestamptz DEFAULT now(),
  UNIQUE(general_account_id, analytical_nature_id)
);

-- Comptes liés aux immobilisations
CREATE TABLE IF NOT EXISTS fixed_asset_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  asset_type text NOT NULL CHECK (asset_type IN (
    'intangible_assets', 'tangible_assets', 'financial_assets',
    'work_in_progress', 'advances_on_orders'
  )),
  asset_account_pattern text NOT NULL, -- Pattern des comptes d'immobilisations
  depreciation_account_pattern text NOT NULL, -- Pattern des comptes d'amortissements
  provision_account_pattern text DEFAULT '', -- Pattern des comptes de dotations
  grant_account_pattern text DEFAULT '', -- Pattern des comptes de subventions
  
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, asset_type)
);

-- RLS
ALTER TABLE account_natures ENABLE ROW LEVEL SECURITY;
ALTER TABLE general_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE thirds ENABLE ROW LEVEL SECURITY;
ALTER TABLE auxiliary_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE automatic_imputations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixed_asset_accounts ENABLE ROW LEVEL SECURITY;

-- Politiques RLS
CREATE POLICY "Users can read account natures"
  ON account_natures FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can access their accounts"
  ON general_accounts FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their thirds"
  ON thirds FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their auxiliary accounts"
  ON auxiliary_accounts FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM general_accounts ga
      JOIN user_permissions up ON ga.company_id = up.company_id
      WHERE ga.id = general_account_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their account tracking"
  ON account_tracking FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their imputations"
  ON automatic_imputations FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM general_accounts ga
      JOIN user_permissions up ON ga.company_id = up.company_id
      WHERE ga.id = general_account_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their fixed asset accounts"
  ON fixed_asset_accounts FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );