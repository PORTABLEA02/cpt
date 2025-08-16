/*
  # Gestion des immobilisations

  1. Tables principales
    - `fixed_asset_locations` - Localisations des immobilisations
    - `fixed_assets` - Éléments immobilisés
    - `asset_depreciation_history` - Historique des amortissements
    - `asset_movements` - Mouvements (entrées/sorties/virements)

  2. Fonctionnalités
    - Calcul automatique des amortissements
    - Suivi des localisations
    - Gestion des sources de financement
    - Virements internes
*/

-- Localisations des immobilisations
CREATE TABLE IF NOT EXISTS fixed_asset_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  
  code text NOT NULL,
  name text NOT NULL,
  parent_code text DEFAULT '', -- Pour sous-groupes
  is_group boolean DEFAULT false,
  description text DEFAULT '',
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, code)
);

-- Éléments immobilisés
CREATE TABLE IF NOT EXISTS fixed_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  -- Identification
  code text NOT NULL,
  name text NOT NULL,
  general_account_id uuid NOT NULL REFERENCES general_accounts(id),
  location_id uuid REFERENCES fixed_asset_locations(id),
  
  -- Dates importantes
  acquisition_date date NOT NULL,
  commissioning_date date, -- Date de mise en service
  disposal_date date, -- Date de sortie
  
  -- Valeurs patrimoniales
  acquisition_value numeric(15,2) NOT NULL DEFAULT 0,
  residual_value numeric(15,2) DEFAULT 0,
  
  -- Amortissement
  depreciation_method text DEFAULT 'linear' CHECK (depreciation_method IN ('linear', 'declining', 'units')),
  depreciation_rate numeric(5,2) DEFAULT 0, -- Taux annuel
  depreciation_years integer DEFAULT 0, -- Durée en années
  
  -- Amortissements calculés
  opening_depreciation numeric(15,2) DEFAULT 0, -- Report amortissements
  current_year_depreciation numeric(15,2) DEFAULT 0, -- Amortissement année
  total_depreciation numeric(15,2) DEFAULT 0, -- Total amortissements
  
  -- Imputations analytiques par défaut
  default_analytical_imputations jsonb DEFAULT '{}',
  
  -- Financement (subventions)
  financing_breakdown jsonb DEFAULT '{"own_funds": 100}', -- Répartition financement
  grant_account_id uuid REFERENCES general_accounts(id), -- Compte de subvention
  
  -- Description et état
  description text DEFAULT '',
  condition text DEFAULT 'good' CHECK (condition IN ('good', 'average', 'poor')),
  serial_number text DEFAULT '',
  supplier_reference text DEFAULT '',
  maintenance_contact text DEFAULT '',
  
  -- État de l'élément
  is_disposed boolean DEFAULT false,
  disposal_type text CHECK (disposal_type IN ('sale', 'destruction', 'internal_transfer')),
  disposal_value numeric(15,2) DEFAULT 0,
  
  -- Contrôle
  is_locked boolean DEFAULT false, -- Verrouillé par calcul amortissement
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, COALESCE(site_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
);

-- Historique des calculs d'amortissements
CREATE TABLE IF NOT EXISTS depreciation_calculations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  calculation_date date NOT NULL,
  calculation_period_start date NOT NULL,
  calculation_period_end date NOT NULL,
  
  -- Statistiques
  assets_count integer DEFAULT 0,
  total_depreciation numeric(15,2) DEFAULT 0,
  
  -- Journal où les écritures sont générées
  journal_id uuid REFERENCES journals(id),
  journal_entry_id uuid REFERENCES journal_entries(id),
  
  performed_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(company_id, fiscal_year_id, calculation_date)
);

-- Détail des amortissements par actif
CREATE TABLE IF NOT EXISTS asset_depreciation_details (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depreciation_calculation_id uuid NOT NULL REFERENCES depreciation_calculations(id) ON DELETE CASCADE,
  fixed_asset_id uuid NOT NULL REFERENCES fixed_assets(id) ON DELETE CASCADE,
  
  opening_value numeric(15,2) NOT NULL,
  depreciation_amount numeric(15,2) NOT NULL,
  closing_value numeric(15,2) NOT NULL,
  
  -- Reprise de subvention si applicable
  grant_reversal_amount numeric(15,2) DEFAULT 0,
  
  created_at timestamptz DEFAULT now()
);

-- Mouvements des immobilisations
CREATE TABLE IF NOT EXISTS asset_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fixed_asset_id uuid NOT NULL REFERENCES fixed_assets(id) ON DELETE CASCADE,
  
  movement_type text NOT NULL CHECK (movement_type IN (
    'acquisition', 'disposal_sale', 'disposal_destruction', 'internal_transfer'
  )),
  movement_date date NOT NULL,
  
  -- Valeurs du mouvement
  movement_value numeric(15,2) DEFAULT 0,
  accumulated_depreciation numeric(15,2) DEFAULT 0,
  net_book_value numeric(15,2) DEFAULT 0,
  
  -- Pour virements internes
  target_account_id uuid REFERENCES general_accounts(id),
  target_asset_code text DEFAULT '',
  
  -- Génération automatique écritures
  journal_entry_id uuid REFERENCES journal_entries(id),
  
  description text DEFAULT '',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE fixed_asset_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixed_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE depreciation_calculations ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_depreciation_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_movements ENABLE ROW LEVEL SECURITY;

-- Politiques RLS
CREATE POLICY "Users can access their asset locations"
  ON fixed_asset_locations FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their fixed assets"
  ON fixed_assets FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their depreciation calculations"
  ON depreciation_calculations FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their depreciation details"
  ON asset_depreciation_details FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM depreciation_calculations dc
      JOIN user_permissions up ON dc.company_id = up.company_id
      WHERE dc.id = depreciation_calculation_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their asset movements"
  ON asset_movements FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM fixed_assets fa
      JOIN user_permissions up ON fa.company_id = up.company_id
      WHERE fa.id = fixed_asset_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );