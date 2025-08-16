/*
  # Paiements et États financiers

  1. Gestion des paiements
    - `payment_schedules` - Programmation des règlements
    - `payment_orders` - Ordres de paiement
    - `payment_receipts` - Réceptions de règlements

  2. États et rapports
    - `financial_statements` - États financiers
    - `tax_declarations` - Déclarations fiscales
    - `balance_carryforwards` - Reports à nouveau
*/

-- Programmation des règlements fournisseurs
CREATE TABLE IF NOT EXISTS payment_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  -- Référence à la facture (ligne d'écriture)
  journal_line_id uuid NOT NULL REFERENCES journal_lines(id) ON DELETE CASCADE,
  third_id uuid NOT NULL REFERENCES thirds(id),
  
  -- Montants
  invoice_amount numeric(15,2) NOT NULL,
  amount_to_pay numeric(15,2) NOT NULL,
  withholding_amount numeric(15,2) DEFAULT 0, -- Retenue à la source
  net_payment_amount numeric(15,2) NOT NULL,
  
  -- Échéances
  due_date date NOT NULL,
  planned_payment_date date,
  
  -- Mode de paiement
  payment_method text NOT NULL CHECK (payment_method IN ('cash', 'check', 'transfer')),
  bank_account_id uuid REFERENCES general_accounts(id),
  
  -- État
  status text DEFAULT 'planned' CHECK (status IN (
    'planned', 'approved', 'executed', 'cancelled'
  )),
  
  -- Contrôle
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Ordres de paiement (bordereaux)
CREATE TABLE IF NOT EXISTS payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  -- Identification
  order_number text NOT NULL,
  order_date date NOT NULL,
  
  -- Banque et mode
  bank_account_id uuid NOT NULL REFERENCES general_accounts(id),
  payment_method text NOT NULL,
  
  -- Pour chèques
  first_check_number text DEFAULT '',
  last_check_number text DEFAULT '',
  
  -- Totaux
  total_amount numeric(15,2) DEFAULT 0,
  payments_count integer DEFAULT 0,
  
  -- Journal comptable généré
  journal_id uuid REFERENCES journals(id),
  journal_entry_id uuid REFERENCES journal_entries(id),
  
  -- État
  is_executed boolean DEFAULT false,
  executed_by uuid REFERENCES auth.users(id),
  executed_at timestamptz,
  
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, order_number)
);

-- Détail des paiements dans un ordre
CREATE TABLE IF NOT EXISTS payment_order_details (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_order_id uuid NOT NULL REFERENCES payment_orders(id) ON DELETE CASCADE,
  payment_schedule_id uuid NOT NULL REFERENCES payment_schedules(id),
  
  -- Informations du paiement
  third_id uuid NOT NULL REFERENCES thirds(id),
  invoice_reference text NOT NULL,
  payment_amount numeric(15,2) NOT NULL,
  withholding_amount numeric(15,2) DEFAULT 0,
  
  -- Numéro de chèque si applicable
  check_number text DEFAULT '',
  
  created_at timestamptz DEFAULT now()
);

-- Affectation des règlements reçus
CREATE TABLE IF NOT EXISTS payment_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  
  -- Référence au règlement (ligne d'écriture)
  journal_line_id uuid NOT NULL REFERENCES journal_lines(id) ON DELETE CASCADE,
  third_id uuid NOT NULL REFERENCES thirds(id),
  
  -- Montants
  receipt_amount numeric(15,2) NOT NULL,
  allocated_amount numeric(15,2) DEFAULT 0,
  remaining_amount numeric(15,2) DEFAULT 0,
  
  -- Mode de règlement
  payment_mode text DEFAULT 'transfer',
  reference text DEFAULT '',
  
  created_at timestamptz DEFAULT now()
);

-- Affectations des règlements aux factures
CREATE TABLE IF NOT EXISTS payment_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_receipt_id uuid NOT NULL REFERENCES payment_receipts(id) ON DELETE CASCADE,
  invoice_line_id uuid NOT NULL REFERENCES journal_lines(id), -- Ligne de facture
  
  allocated_amount numeric(15,2) NOT NULL,
  allocation_date timestamptz DEFAULT now(),
  
  created_by uuid REFERENCES auth.users(id)
);

-- États financiers (résultats de calculs)
CREATE TABLE IF NOT EXISTS financial_statements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  -- Période et type
  statement_date date NOT NULL,
  statement_type text NOT NULL CHECK (statement_type IN (
    'trial_balance', 'balance_sheet', 'income_statement', 'cash_flow'
  )),
  
  -- Configuration
  accounting_system text DEFAULT 'normal' CHECK (accounting_system IN ('normal', 'simplified')),
  include_inventory boolean DEFAULT true,
  include_result boolean DEFAULT true,
  
  -- Données (JSON pour flexibilité)
  statement_data jsonb NOT NULL DEFAULT '{}',
  
  -- Contrôle
  calculated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(company_id, fiscal_year_id, statement_date, statement_type)
);

-- Déclarations fiscales et déductions
CREATE TABLE IF NOT EXISTS tax_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  
  -- Type de déclaration
  declaration_type text NOT NULL CHECK (declaration_type IN (
    'vat', 'withholding_tax', 'corporate_tax', 'annual_return'
  )),
  
  -- Période
  period_start date NOT NULL,
  period_end date NOT NULL,
  
  -- Déductions et réintégrations fiscales
  tax_deductions jsonb DEFAULT '{}',
  tax_reintegrations jsonb DEFAULT '{}',
  
  -- Calculs
  taxable_base numeric(15,2) DEFAULT 0,
  tax_rate numeric(5,2) DEFAULT 0,
  calculated_tax numeric(15,2) DEFAULT 0,
  minimum_tax numeric(15,2) DEFAULT 0,
  final_tax_due numeric(15,2) DEFAULT 0,
  
  -- Comptes d'imputation
  tax_expense_account_id uuid REFERENCES general_accounts(id),
  tax_payable_account_id uuid REFERENCES general_accounts(id),
  
  -- État
  is_calculated boolean DEFAULT false,
  is_filed boolean DEFAULT false,
  filing_date date,
  
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Reports à nouveau
CREATE TABLE IF NOT EXISTS balance_carryforwards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  site_id uuid REFERENCES sites(id) ON DELETE CASCADE,
  
  -- Compte concerné
  general_account_id uuid NOT NULL REFERENCES general_accounts(id),
  
  -- Montants de report
  carryforward_debit numeric(15,2) DEFAULT 0,
  carryforward_credit numeric(15,2) DEFAULT 0,
  
  -- Pour comptes avec suivi spécial (détail des lignes)
  detail_lines jsonb DEFAULT '[]', -- Pour lettrables, pointables, à payer/recevoir
  
  -- Imputations analytiques si requises
  analytical_carryforwards jsonb DEFAULT '{}',
  
  -- Contrôle
  is_locked boolean DEFAULT false,
  transferred_from_previous boolean DEFAULT false, -- Transféré auto depuis exercice précédent
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, fiscal_year_id, COALESCE(site_id, '00000000-0000-0000-0000-000000000000'::uuid), general_account_id)
);

-- RLS
ALTER TABLE payment_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_order_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE balance_carryforwards ENABLE ROW LEVEL SECURITY;

-- Politiques RLS globales (utilisateurs autorisés par société)
CREATE POLICY "Users can access company payment data"
  ON payment_schedules FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access company payment orders"
  ON payment_orders FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access payment order details"
  ON payment_order_details FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM payment_orders po
      JOIN user_permissions up ON po.company_id = up.company_id
      WHERE po.id = payment_order_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access company receipts"
  ON payment_receipts FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access payment allocations"
  ON payment_allocations FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM payment_receipts pr
      JOIN user_permissions up ON pr.company_id = up.company_id
      WHERE pr.id = payment_receipt_id 
      AND up.user_id = auth.uid() 
      AND up.is_active = true
    )
  );

CREATE POLICY "Users can access their financial statements"
  ON financial_statements FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their tax declarations"
  ON tax_declarations FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can access their carryforwards"
  ON balance_carryforwards FOR ALL
  TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM user_permissions 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );