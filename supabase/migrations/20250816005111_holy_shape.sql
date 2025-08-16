/*
  # Index et fonctions utilitaires

  1. Index de performance
  2. Fonctions utilitaires
  3. Triggers de mise à jour automatique
  4. Vues pour requêtes complexes
*/

-- INDEX DE PERFORMANCE

-- Index sur les comptes et exercices (très utilisés)
CREATE INDEX IF NOT EXISTS idx_general_accounts_company_year_code 
  ON general_accounts(company_id, fiscal_year_id, code);

CREATE INDEX IF NOT EXISTS idx_journal_lines_account_date 
  ON journal_lines(general_account_id, journal_entry_id);

CREATE INDEX IF NOT EXISTS idx_journal_entries_journal_date 
  ON journal_entries(journal_id, entry_date);

-- Index sur les tiers et comptes auxiliaires
CREATE INDEX IF NOT EXISTS idx_thirds_company_type_code 
  ON thirds(company_id, type, code);

CREATE INDEX IF NOT EXISTS idx_auxiliary_accounts_third 
  ON auxiliary_accounts(third_id);

-- Index sur les imputations analytiques
CREATE INDEX IF NOT EXISTS idx_journal_lines_analytical 
  ON journal_lines USING gin(analytical_imputations);

-- Index sur les immobilisations
CREATE INDEX IF NOT EXISTS idx_fixed_assets_company_year_account 
  ON fixed_assets(company_id, fiscal_year_id, general_account_id);

-- Index sur les suivis (lettrage, pointage)
CREATE INDEX IF NOT EXISTS idx_journal_lines_letter_pointed 
  ON journal_lines(letter_code, is_pointed) WHERE letter_code != '' OR is_pointed = true;

-- Index sur les paiements
CREATE INDEX IF NOT EXISTS idx_payment_schedules_third_date 
  ON payment_schedules(third_id, due_date);

-- FONCTIONS UTILITAIRES

-- Fonction pour calculer le solde d'un compte
CREATE OR REPLACE FUNCTION calculate_account_balance(
  p_account_id uuid,
  p_end_date date DEFAULT CURRENT_DATE
) RETURNS numeric(15,2) AS $$
DECLARE
  account_balance numeric(15,2) := 0;
BEGIN
  SELECT 
    COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0)
  INTO account_balance
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_entry_id = je.id
  WHERE jl.general_account_id = p_account_id
    AND je.entry_date <= p_end_date
    AND je.is_balanced = true;
    
  RETURN COALESCE(account_balance, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour générer le code d'un compte auxiliaire
CREATE OR REPLACE FUNCTION generate_auxiliary_account_code(
  p_collective_account_code text,
  p_third_code text
) RETURNS text AS $$
BEGIN
  RETURN p_collective_account_code || p_third_code;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Fonction pour vérifier si un utilisateur peut accéder à une société
CREATE OR REPLACE FUNCTION user_can_access_company(
  p_user_id uuid,
  p_company_id uuid
) RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_permissions 
    WHERE user_id = p_user_id 
      AND company_id = p_company_id 
      AND is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- TRIGGERS DE MISE À JOUR

-- Trigger pour mettre à jour automatiquement les totaux des pièces comptables
CREATE OR REPLACE FUNCTION update_journal_entry_totals()
RETURNS trigger AS $$
BEGIN
  UPDATE journal_entries 
  SET 
    total_debit = (
      SELECT COALESCE(SUM(debit), 0) 
      FROM journal_lines 
      WHERE journal_entry_id = COALESCE(NEW.journal_entry_id, OLD.journal_entry_id)
    ),
    total_credit = (
      SELECT COALESCE(SUM(credit), 0) 
      FROM journal_lines 
      WHERE journal_entry_id = COALESCE(NEW.journal_entry_id, OLD.journal_entry_id)
    ),
    updated_at = now()
  WHERE id = COALESCE(NEW.journal_entry_id, OLD.journal_entry_id);
  
  -- Marquer comme équilibrée si débit = crédit
  UPDATE journal_entries
  SET is_balanced = (total_debit = total_credit AND total_debit > 0)
  WHERE id = COALESCE(NEW.journal_entry_id, OLD.journal_entry_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_journal_entry_totals
  AFTER INSERT OR UPDATE OR DELETE ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION update_journal_entry_totals();

-- Trigger pour créer automatiquement les comptes auxiliaires
CREATE OR REPLACE FUNCTION create_auxiliary_account_if_needed()
RETURNS trigger AS $$
DECLARE
  collective_account general_accounts%ROWTYPE;
  auxiliary_code text;
BEGIN
  -- Vérifier si c'est un compte collectif
  SELECT * INTO collective_account 
  FROM general_accounts 
  WHERE id = NEW.general_account_id AND is_collective = true;
  
  IF FOUND AND NEW.third_id IS NOT NULL THEN
    -- Générer le code du compte auxiliaire
    SELECT generate_auxiliary_account_code(collective_account.code, t.code)
    INTO auxiliary_code
    FROM thirds t
    WHERE t.id = NEW.third_id;
    
    -- Créer le compte auxiliaire s'il n'existe pas
    INSERT INTO auxiliary_accounts (general_account_id, third_id, code, name)
    SELECT 
      NEW.general_account_id,
      NEW.third_id,
      auxiliary_code,
      collective_account.name || ' - ' || t.name
    FROM thirds t
    WHERE t.id = NEW.third_id
      AND NOT EXISTS (
        SELECT 1 FROM auxiliary_accounts 
        WHERE general_account_id = NEW.general_account_id 
          AND third_id = NEW.third_id
      );
      
    -- Mettre à jour la ligne avec le compte auxiliaire
    SELECT id INTO NEW.auxiliary_account_id
    FROM auxiliary_accounts
    WHERE general_account_id = NEW.general_account_id 
      AND third_id = NEW.third_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_auxiliary_account
  BEFORE INSERT ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION create_auxiliary_account_if_needed();

-- VUES UTILITAIRES

-- Vue pour la balance générale
CREATE OR REPLACE VIEW v_general_balance AS
SELECT 
  ga.company_id,
  ga.fiscal_year_id,
  ga.site_id,
  ga.id as account_id,
  ga.code as account_code,
  ga.name as account_name,
  ga.is_group,
  ga.parent_code,
  
  -- Reports à nouveau
  COALESCE(bc.carryforward_debit, 0) as opening_debit,
  COALESCE(bc.carryforward_credit, 0) as opening_credit,
  
  -- Mouvements de la période
  COALESCE(SUM(jl.debit), 0) as period_debit,
  COALESCE(SUM(jl.credit), 0) as period_credit,
  
  -- Soldes
  (COALESCE(bc.carryforward_debit, 0) + COALESCE(SUM(jl.debit), 0)) as total_debit,
  (COALESCE(bc.carryforward_credit, 0) + COALESCE(SUM(jl.credit), 0)) as total_credit,
  
  -- Solde final
  (COALESCE(bc.carryforward_debit, 0) + COALESCE(SUM(jl.debit), 0)) - 
  (COALESCE(bc.carryforward_credit, 0) + COALESCE(SUM(jl.credit), 0)) as balance

FROM general_accounts ga
LEFT JOIN balance_carryforwards bc ON ga.id = bc.general_account_id
LEFT JOIN journal_lines jl ON ga.id = jl.general_account_id
LEFT JOIN journal_entries je ON jl.journal_entry_id = je.id AND je.is_balanced = true
WHERE ga.is_active = true
GROUP BY 
  ga.company_id, ga.fiscal_year_id, ga.site_id, ga.id, ga.code, ga.name, 
  ga.is_group, ga.parent_code, bc.carryforward_debit, bc.carryforward_credit;

-- Vue pour les soldes des tiers
CREATE OR REPLACE VIEW v_third_party_balances AS
SELECT 
  t.company_id,
  t.id as third_id,
  t.code as third_code,
  t.name as third_name,
  t.type as third_type,
  
  -- Totaux tous comptes auxiliaires confondus
  COALESCE(SUM(jl.debit), 0) as total_debit,
  COALESCE(SUM(jl.credit), 0) as total_credit,
  COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) as balance,
  
  -- Nombre de factures/références distinctes
  COUNT(DISTINCT jl.reference) FILTER (WHERE jl.reference != '') as references_count

FROM thirds t
LEFT JOIN auxiliary_accounts aa ON t.id = aa.third_id
LEFT JOIN journal_lines jl ON aa.id = jl.auxiliary_account_id
LEFT JOIN journal_entries je ON jl.journal_entry_id = je.id AND je.is_balanced = true
WHERE t.is_active = true
GROUP BY t.company_id, t.id, t.code, t.name, t.type;

-- Vue pour le suivi des immobilisations
CREATE OR REPLACE VIEW v_fixed_assets_summary AS
SELECT 
  fa.company_id,
  fa.fiscal_year_id,
  fa.id as asset_id,
  fa.code as asset_code,
  fa.name as asset_name,
  ga.code as account_code,
  ga.name as account_name,
  fal.name as location_name,
  
  fa.acquisition_date,
  fa.commissioning_date,
  fa.disposal_date,
  fa.is_disposed,
  
  fa.acquisition_value,
  fa.opening_depreciation,
  fa.current_year_depreciation,
  fa.total_depreciation,
  fa.acquisition_value - fa.total_depreciation as net_book_value,
  
  fa.depreciation_rate,
  fa.depreciation_years,
  fa.condition

FROM fixed_assets fa
JOIN general_accounts ga ON fa.general_account_id = ga.id
LEFT JOIN fixed_asset_locations fal ON fa.location_id = fal.id
WHERE fa.is_active = true;

-- Accorder les permissions sur les vues
GRANT SELECT ON v_general_balance TO authenticated;
GRANT SELECT ON v_third_party_balances TO authenticated;
GRANT SELECT ON v_fixed_assets_summary TO authenticated;