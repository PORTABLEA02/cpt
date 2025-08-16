/*
  # Données d'exemple pour Perfecto Comptabilité

  1. Cadres comptables de base
  2. Devises principales
  3. Natures de comptes OHADA
  4. Données de démonstration
*/

-- Insertion des cadres comptables
INSERT INTO accounting_frameworks (code, name, description, country) VALUES
('OHADA', 'Système comptable OHADA', 'Plan comptable harmonisé des pays de la zone OHADA', 'West Africa'),
('BANCAIRE_UEMOA', 'Plan comptable bancaire UEMOA', 'Plan comptable spécifique aux banques UEMOA', 'West Africa'),
('ASSURANCES', 'Plan comptable des assurances', 'Plan comptable pour les compagnies d''assurance', 'General'),
('MICROFINANCE', 'Plan comptable microfinance', 'Plan comptable pour les institutions de microfinance', 'General')
ON CONFLICT (code) DO NOTHING;

-- Insertion des devises
INSERT INTO currencies (code, name, symbol, is_base, last_rate) VALUES
('XOF', 'Franc CFA (BCEAO)', 'FCFA', true, 1.0),
('EUR', 'Euro', '€', false, 655.957),
('USD', 'Dollar américain', '$', false, 580.0),
('XAF', 'Franc CFA (BEAC)', 'FCFA', false, 1.0)
ON CONFLICT (code) DO NOTHING;

-- Insertion des natures de comptes OHADA principales
DO $$
DECLARE
  ohada_id uuid;
BEGIN
  SELECT id INTO ohada_id FROM accounting_frameworks WHERE code = 'OHADA';
  
  INSERT INTO account_natures (accounting_framework_id, code, name, category) VALUES
  -- Classe 1 - Comptes de ressources durables
  (ohada_id, '1', 'Comptes de ressources durables', 'equity'),
  (ohada_id, '10', 'Capital', 'equity'),
  (ohada_id, '11', 'Réserves', 'equity'),
  (ohada_id, '12', 'Report à nouveau', 'equity'),
  (ohada_id, '13', 'Résultat net de l''exercice', 'equity'),
  (ohada_id, '14', 'Subventions d''investissement', 'equity'),
  (ohada_id, '15', 'Provisions réglementées', 'equity'),
  (ohada_id, '16', 'Emprunts et dettes', 'liabilities'),
  (ohada_id, '18', 'Dettes liées aux participations', 'liabilities'),
  (ohada_id, '19', 'Provisions financières', 'liabilities'),
  
  -- Classe 2 - Comptes d'actif immobilisé
  (ohada_id, '2', 'Comptes d''actif immobilisé', 'assets'),
  (ohada_id, '20', 'Charges immobilisées', 'assets'),
  (ohada_id, '21', 'Immobilisations incorporelles', 'fixed_assets'),
  (ohada_id, '22', 'Terrains', 'fixed_assets'),
  (ohada_id, '23', 'Bâtiments, installations techniques', 'fixed_assets'),
  (ohada_id, '24', 'Matériel', 'fixed_assets'),
  (ohada_id, '26', 'Titres de participation', 'fixed_assets'),
  (ohada_id, '27', 'Autres immobilisations financières', 'assets'),
  (ohada_id, '28', 'Amortissements', 'depreciation'),
  (ohada_id, '29', 'Provisions pour dépréciation', 'assets'),
  
  -- Classe 3 - Comptes de stocks
  (ohada_id, '3', 'Comptes de stocks', 'assets'),
  (ohada_id, '31', 'Matières premières', 'assets'),
  (ohada_id, '32', 'Autres approvisionnements', 'assets'),
  (ohada_id, '33', 'En-cours de production', 'assets'),
  (ohada_id, '34', 'Produits intermédiaires', 'assets'),
  (ohada_id, '35', 'Produits finis', 'assets'),
  (ohada_id, '36', 'Produits résiduels', 'assets'),
  (ohada_id, '37', 'Stocks de marchandises', 'assets'),
  (ohada_id, '38', 'Stocks en cours de route', 'assets'),
  (ohada_id, '39', 'Provisions pour dépréciation des stocks', 'assets'),
  
  -- Classe 4 - Comptes de tiers
  (ohada_id, '4', 'Comptes de tiers', 'assets'),
  (ohada_id, '40', 'Fournisseurs et comptes rattachés', 'suppliers'),
  (ohada_id, '41', 'Clients et comptes rattachés', 'customers'),
  (ohada_id, '42', 'Personnel', 'personnel'),
  (ohada_id, '43', 'Organismes sociaux', 'misc_third_parties'),
  (ohada_id, '44', 'État et collectivités publiques', 'misc_third_parties'),
  (ohada_id, '45', 'Organismes internationaux', 'misc_third_parties'),
  (ohada_id, '46', 'Associés et groupe', 'misc_third_parties'),
  (ohada_id, '47', 'Débiteurs et créditeurs divers', 'misc_third_parties'),
  (ohada_id, '48', 'Créances et dettes d''exploitation', 'assets'),
  (ohada_id, '49', 'Provisions pour dépréciation', 'assets'),
  
  -- Classe 5 - Comptes de trésorerie
  (ohada_id, '5', 'Comptes de trésorerie', 'assets'),
  (ohada_id, '50', 'Titres de placement', 'assets'),
  (ohada_id, '51', 'Banques, établissements financiers', 'assets'),
  (ohada_id, '52', 'Banques, établissements financiers', 'assets'),
  (ohada_id, '53', 'Caisses', 'assets'),
  (ohada_id, '54', 'Régies d''avances', 'assets'),
  (ohada_id, '58', 'Virements internes', 'assets'),
  (ohada_id, '59', 'Provisions pour dépréciation', 'assets'),
  
  -- Classe 6 - Comptes de charges
  (ohada_id, '6', 'Comptes de charges', 'expenses'),
  (ohada_id, '60', 'Achats et variations de stocks', 'expenses'),
  (ohada_id, '61', 'Transports', 'expenses'),
  (ohada_id, '62', 'Services extérieurs A', 'expenses'),
  (ohada_id, '63', 'Services extérieurs B', 'expenses'),
  (ohada_id, '64', 'Impôts et taxes', 'expenses'),
  (ohada_id, '65', 'Autres charges', 'expenses'),
  (ohada_id, '66', 'Charges de personnel', 'expenses'),
  (ohada_id, '67', 'Frais financiers', 'expenses'),
  (ohada_id, '68', 'Dotations aux amortissements', 'expenses'),
  (ohada_id, '69', 'Charges exceptionnelles', 'expenses'),
  
  -- Classe 7 - Comptes de produits
  (ohada_id, '7', 'Comptes de produits', 'income'),
  (ohada_id, '70', 'Ventes', 'income'),
  (ohada_id, '71', 'Subventions d''exploitation', 'income'),
  (ohada_id, '72', 'Production immobilisée', 'income'),
  (ohada_id, '73', 'Variations des stocks de biens', 'income'),
  (ohada_id, '74', 'Autres produits', 'income'),
  (ohada_id, '75', 'Autres produits', 'income'),
  (ohada_id, '76', 'Produits financiers', 'income'),
  (ohada_id, '77', 'Revenus financiers', 'income'),
  (ohada_id, '78', 'Reprises d''amortissements', 'income'),
  (ohada_id, '79', 'Produits exceptionnels', 'income')
  
  ON CONFLICT (accounting_framework_id, code) DO NOTHING;
  
  -- Marquer les comptes de TVA
  UPDATE account_natures SET 
    is_vat_deductible = true 
  WHERE accounting_framework_id = ohada_id 
    AND code IN ('4451', '4452', '4453', '4454', '4455', '4456', '4457', '4458');
    
  UPDATE account_natures SET 
    is_vat_collectible = true 
  WHERE accounting_framework_id = ohada_id 
    AND code = '4435';

  -- Marquer les comptes de tiers
  UPDATE account_natures SET 
    is_supplier = true 
  WHERE accounting_framework_id = ohada_id 
    AND code LIKE '40%';
    
  UPDATE account_natures SET 
    is_customer = true 
  WHERE accounting_framework_id = ohada_id 
    AND code LIKE '41%';
    
  UPDATE account_natures SET 
    is_personnel = true 
  WHERE accounting_framework_id = ohada_id 
    AND code LIKE '42%';
    
  UPDATE account_natures SET 
    is_misc_third = true 
  WHERE accounting_framework_id = ohada_id 
    AND code IN ('43', '44', '45', '46', '47');

END $$;

-- Message de confirmation
DO $$
BEGIN
  RAISE NOTICE 'Base de données Perfecto Comptabilité créée avec succès !';
  RAISE NOTICE 'Cadres comptables disponibles: OHADA, Bancaire UEMOA, Assurances, Microfinance';
  RAISE NOTICE 'Devises configurées: XOF (base), EUR, USD, XAF';
  RAISE NOTICE 'Structure complète pour comptabilité multi-sociétés, multi-devises, multi-sites';
END $$;