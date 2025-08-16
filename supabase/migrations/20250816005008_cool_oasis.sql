/*
  # Marchés/Commandes et Budgets

  1. Gestion des marchés fournisseurs
    - `contracts` - Bons de commande, contrats
    - `contract_lines` - Détail des engagements
    - `contract_tracking` - Suivi réalisation/paiements

  2. Gestion budgétaire
    - `budgets` - Définition des budgets
    - `budget_lines` - Lignes budgétaires
    - `budget_execution` - Suivi exécution
*/

-- Marchés/Commandes aux fournisseurs
CREATE TABLE IF NOT EXISTS contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  -- Identification
  reference text NOT NULL, -- Numéro bon commande, contrat
  nature text NOT NULL DEFAULT 'purchase_order', -- bon_commande, lettre_commande, contrat
  contract_date date NOT NULL,
  
  -- Fournisseur
  supplier_id uuid NOT NULL REFERENCES thirds(id),
  
  -- Contenu
  title text NOT NULL,
  description text DEFAULT '',
  
  -- Montants
  total_amount_ht numeric(15,2) DEFAULT 0,
  total_amount_ttc numeric(15,2) DEFAULT 0,
  vat_amount numeric(15,2) DEFAULT 0,
  
  -- Échéances
  delivery_date date,
  expected_completion_date date,
  actual_completion_date date,
  
  -- État
  status text DEFAULT 'draft' CHECK (status IN (
    'draft', 'sent', 'confirmed', 'in_progress', 'completed', 'cancelled'
  )),
  is_controlled boolean DEFAULT false,
  controlled_by uuid REFERENCES auth.users(id),
  controlled_at timestamptz,
  
  -- Imputations analytiques par défaut
  default_analytical_imputations jsonb DEFAULT '{}',
  
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, reference)
);

-- Lignes de marchés/engagements donnés
CREATE TABLE IF NOT EXISTS contract_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
  line_number integer NOT NULL DEFAULT 1,
  
  -- Imputation comptable
  general_account_id uuid REFERENCES general_accounts(id),
  
  -- Description de l'engagement
  designation text NOT NULL,
  quantity numeric(12,3) DEFAULT 1,
  unit_price numeric(15,2) DEFAULT 0,
  
  -- Montants
  amount_ht numeric(15,2) NOT NULL DEFAULT 0,
  vat_rate numeric(5,2) DEFAULT 0,
  vat_amount numeric(15,2) DEFAULT 0,
  amount_ttc numeric(15,2) DEFAULT 0,
  
  -- Imputations analytiques spécifiques
  analytical_imputations jsonb DEFAULT '{}',
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(contract_id, line_number)
);

-- Suivi des marchés (réalisation, avances, paiements)
CREATE TABLE IF NOT EXISTS contract_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
  
  -- Reports (pour exercices antérieurs)
  advances_carryforward numeric(15,2) DEFAULT 0,
  realization_carryforward numeric(15,2) DEFAULT 0,
  payments_carryforward numeric(15,2) DEFAULT 0,
  retentions_carryforward numeric(15,2) DEFAULT 0,
  
  -- Mouvements exercice
  advances_current numeric(15,2) DEFAULT 0,
  realization_current numeric(15,2) DEFAULT 0,
  payments_current numeric(15,2) DEFAULT 0,
  retentions_current numeric(15,2) DEFAULT 0,
  
  -- Totaux calculés
  total_advances numeric(15,2) DEFAULT 0,
  total_realization numeric(15,2) DEFAULT 0,
  total_payments numeric(15,2) DEFAULT 0,
  total_retentions numeric(15,2) DEFAULT 0,
  
  last_updated timestamptz DEFAULT now()
);

-- Budgets prévisionnels
CREATE TABLE IF NOT EXISTS budgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  -- Identification
  code text NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  
  -- Période
  period_start date NOT NULL,
  period_end date NOT NULL,
  
  -- Configuration
  budget_type text NOT NULL CHECK (budget_type IN (
    'investment', 'operating_expenses', 'operating_income', 'treasury'
  )),
  
  -- Décomposition temporelle
  time_breakdown text DEFAULT 'none' CHECK (time_breakdown IN ('none', 'monthly', 'quarterly')),
  
  -- Comptes concernés
  account_pattern text DEFAULT '*', -- Pattern des comptes concernés
  movement_direction text DEFAULT 'debit' CHECK (movement_direction IN ('debit', 'credit', 'both')),
  
  -- Classification analytique
  analytical_classification jsonb DEFAULT '{}', -- Ordre de classement
  
  -- Totaux
  total_budget numeric(15,2) DEFAULT 0,
  total_commitments numeric(15,2) DEFAULT 0,
  total_realization numeric(15,2) DEFAULT 0,
  remaining_budget numeric(15,2) DEFAULT 0,
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, COALESCE(site_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
);

-- Lignes budgétaires
CREATE TABLE IF NOT EXISTS budget_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  budget_id uuid NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
  
  -- Classification
  general_account_code text NOT NULL, -- Peut être regroupement
  analytical_imputations jsonb DEFAULT '{}', -- Codes analytiques
  
  -- Montants budgétés
  budgeted_amount numeric(15,2) NOT NULL DEFAULT 0,
  
  -- Décomposition mensuelle/trimestrielle si activée
  monthly_breakdown numeric(15,2)[] DEFAULT ARRAY[0,0,0,0,0,0,0,0,0,0,0,0],
  quarterly_breakdown numeric(15,2)[] DEFAULT ARRAY[0,0,0,0],
  
  -- Suivi d'exécution
  committed_amount numeric(15,2) DEFAULT 0, -- Engagements
  realized_amount numeric(15,2) DEFAULT 0, -- Réalisations
  remaining_amount numeric(15,2) DEFAULT 0, -- Disponible
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Abonnements (opérations récurrentes)
CREATE TABLE IF NOT EXISTS subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  code text NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  
  -- Périodicité
  frequency text NOT NULL CHECK (frequency IN ('monthly', 'quarterly', 'yearly')),
  start_date date NOT NULL,
  end_date date,
  next_generation_date date,
  
  -- Modèle d'écriture
  template_entry jsonb NOT NULL, -- Structure de l'écriture type
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, code)
);

-- RLS
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Politiques RLS
CREATE POLICY "Users can access their contracts"
  ON contracts FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their contract lines"
  ON contract_lines FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM contracts c
      JOIN user_permissions up ON c.company_id = up.company_id
      WHERE c.id = contract_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their contract tracking"
  ON contract_tracking FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM contracts c
      JOIN user_permissions up ON c.company_id = up.company_id
      WHERE c.id = contract_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their budgets"
  ON budgets FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their budget lines"
  ON budget_lines FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM budgets b
      JOIN user_permissions up ON b.company_id = up.company_id
      WHERE b.id = budget_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their subscriptions"
  ON subscriptions FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );