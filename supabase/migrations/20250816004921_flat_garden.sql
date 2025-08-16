/*
  # Journaux et écritures comptables

  1. Tables principales
    - `journals` - Journaux comptables
    - `journal_entries` - Pièces comptables
    - `journal_lines` - Lignes d'écriture
    - `document_attachments` - Documents numérisés

  2. Configuration
    - Types de journaux
    - Numérotation des pièces
    - Contrôles et validations
*/

-- Journaux comptables
CREATE TABLE IF NOT EXISTS journals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  code text NOT NULL,
  name text NOT NULL,
  
  nature text NOT NULL CHECK (nature IN (
    'current_operations', 'automatic_depreciation', 'fiscal_result',
    'subscriptions', 'centralization', 'real_time_cash', 'inventory'
  )),
  
  -- Configuration
  allowed_accounts text DEFAULT '*', -- Pattern des comptes autorisés
  piece_numbering_reset text DEFAULT 'yearly' CHECK (piece_numbering_reset IN (
    'never', 'daily', 'monthly', 'yearly'
  )),
  
  -- État
  is_closed boolean DEFAULT false,
  closure_date date,
  current_piece_number integer DEFAULT 0,
  
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, COALESCE(site_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
);

-- Pièces comptables
CREATE TABLE IF NOT EXISTS journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_id uuid NOT NULL REFERENCES journals(id) ON DELETE CASCADE,
  
  piece_number text NOT NULL,
  entry_date date NOT NULL,
  
  -- État de la pièce
  is_balanced boolean DEFAULT false,
  is_in_progress boolean DEFAULT false, -- Pièce en cours de saisie
  total_debit numeric(15,2) DEFAULT 0,
  total_credit numeric(15,2) DEFAULT 0,
  
  -- Audit
  created_by uuid REFERENCES auth.users(id),
  last_modified_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  UNIQUE(journal_id, piece_number)
);

-- Lignes d'écriture
CREATE TABLE IF NOT EXISTS journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id uuid NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  line_number integer NOT NULL DEFAULT 1,
  
  -- Compte et tiers
  general_account_id uuid NOT NULL REFERENCES general_accounts(id),
  auxiliary_account_id uuid REFERENCES auxiliary_accounts(id),
  third_id uuid REFERENCES thirds(id),
  
  -- Montants
  debit numeric(15,2) DEFAULT 0,
  credit numeric(15,2) DEFAULT 0,
  currency_id uuid REFERENCES currencies(id),
  currency_amount numeric(15,2) DEFAULT 0,
  currency_rate numeric(10,6) DEFAULT 1,
  
  -- Informations complémentaires
  reference text DEFAULT '', -- Référence facture, chèque, etc.
  description text NOT NULL,
  due_date date, -- Pour comptes à payer/recevoir
  is_internal_transfer boolean DEFAULT false,
  
  -- Imputations analytiques (JSON pour flexibilité)
  analytical_imputations jsonb DEFAULT '{}',
  
  -- Suivi
  letter_code text DEFAULT '', -- Pour lettrage
  is_pointed boolean DEFAULT false,
  pointing_date date,
  
  -- Liens
  fixed_asset_id uuid, -- Référence vers immobilisation
  contract_id uuid, -- Référence vers marché/commande
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(journal_entry_id, line_number)
);

-- Documents numérisés attachés
CREATE TABLE IF NOT EXISTS document_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_line_id uuid NOT NULL REFERENCES journal_lines(id) ON DELETE CASCADE,
  
  file_name text NOT NULL,
  file_type text NOT NULL,
  file_size bigint NOT NULL,
  file_path text NOT NULL, -- Chemin vers le fichier stocké
  
  description text DEFAULT '',
  uploaded_by uuid REFERENCES auth.users(id),
  uploaded_at timestamptz DEFAULT now()
);

-- Raccourcis de saisie
CREATE TABLE IF NOT EXISTS entry_shortcuts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id), -- null = global à la société
  
  shortcut_key char(1) NOT NULL, -- A-Z
  shortcut_text text NOT NULL,
  
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), shortcut_key)
);

-- Contrôles de cohérence
CREATE TABLE IF NOT EXISTS balance_controls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  control_date date NOT NULL,
  control_type text NOT NULL,
  journal_id uuid REFERENCES journals(id),
  
  anomalies_found integer DEFAULT 0,
  anomaly_details text DEFAULT '',
  
  performed_by uuid REFERENCES auth.users(id),
  performed_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE entry_shortcuts ENABLE ROW LEVEL SECURITY;
ALTER TABLE balance_controls ENABLE ROW LEVEL SECURITY;

-- Politiques RLS
CREATE POLICY "Users can access their journals"
  ON journals FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their journal entries"
  ON journal_entries FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM journals j
      JOIN user_permissions up ON j.company_id = up.company_id
      WHERE j.id = journal_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their journal lines"
  ON journal_lines FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM journal_entries je
      JOIN journals j ON je.journal_id = j.id
      JOIN user_permissions up ON j.company_id = up.company_id
      WHERE je.id = journal_entry_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their document attachments"
  ON document_attachments FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM journal_lines jl
      JOIN journal_entries je ON jl.journal_entry_id = je.id
      JOIN journals j ON je.journal_id = j.id
      JOIN user_permissions up ON j.company_id = up.company_id
      WHERE jl.id = journal_line_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their shortcuts"
  ON entry_shortcuts FOR ALL
  TO authenticated
  USING (
    (user_id = auth.uid() OR user_id IS NULL) AND
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their controls"
  ON balance_controls FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );