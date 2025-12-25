#!/usr/bin/env python3
import subprocess

# Configuration
DB_NAME = "nova_syndicate"
DB_USER = "yepa177"
DB_PASSWORD = "qwerty123"  # Remplace par ton mot de passe
POD_NAME = "postgresql-clean-0"
NAMESPACE = "nova-syndicate"
CSV_DIR = "/tmp"  # Dans le pod

# Tables et leurs schémas
TABLES = {
    "collaborateurs": """
        CREATE TABLE IF NOT EXISTS collaborateurs (
            id_collaborateur SERIAL PRIMARY KEY,
            nom VARCHAR(100),
            prenom VARCHAR(100),
            email VARCHAR(100),
            poste VARCHAR(50),
            site VARCHAR(50),
            date_embauche DATE
        );
    """,
    "clients": """
        CREATE TABLE IF NOT EXISTS clients (
            id_client SERIAL PRIMARY KEY,
            nom_entreprise VARCHAR(100),
            secteur VARCHAR(100),
            contact_nom VARCHAR(100),
            contact_prenom VARCHAR(100),
            email_contact VARCHAR(100),
            telephone VARCHAR(20)
        );
    """,
    "produits_medicaux": """
        CREATE TABLE IF NOT EXISTS produits_medicaux (
            id_produit SERIAL PRIMARY KEY,
            nom_produit VARCHAR(100),
            description TEXT,
            prix_unitaire DECIMAL(10, 2),
            stock INT
        );
    """,
    "produits_aerospatiaux": """
        CREATE TABLE IF NOT EXISTS produits_aerospatiaux (
            id_produit SERIAL PRIMARY KEY,
            nom_produit VARCHAR(100),
            description TEXT,
            prix_unitaire DECIMAL(10, 2),
            stock INT
        );
    """,
    "commandes": """
        CREATE TABLE IF NOT EXISTS commandes (
            id_commande SERIAL PRIMARY KEY,
            id_client INT REFERENCES clients(id_client),
            date_commande DATE,
            montant_total DECIMAL(10, 2),
            statut VARCHAR(20)
        );
    """
}

# Mappage des fichiers CSV aux tables
CSV_FILES = {
    "collaborateurs": "collaborateurs.csv",
    "clients": "clients.csv",
    "produits_medicaux": "produits_medicaux.csv",
    "produits_aerospatiaux": "produits_aerospatiaux.csv",
    "commandes": "commandes.csv"
}

def run_command(cmd):
    """Exécute une commande shell et retourne le résultat."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ Erreur: {result.stderr}")
        return False
    print(result.stdout)
    return True

def drop_tables():
    """Supprime les tables existantes."""
    print("🗑️  Suppression des tables existantes...")
    for table_name in TABLES.keys():
        cmd = f"kubectl exec {POD_NAME} -n {NAMESPACE} -- bash -c \"PGPASSWORD='{DB_PASSWORD}' psql -U {DB_USER} -d {DB_NAME} -c 'DROP TABLE IF EXISTS {table_name} CASCADE;\""
        run_command(cmd)

def create_tables():
    """Crée les tables via kubectl exec."""
    print("🛠️  Création des tables...")
    for table_name, create_sql in TABLES.items():
        cmd = f"kubectl exec {POD_NAME} -n {NAMESPACE} -- bash -c \"PGPASSWORD='{DB_PASSWORD}' psql -U {DB_USER} -d {DB_NAME} -c \\\"{create_sql}\\\"\""
        if not run_command(cmd):
            return False
    return True

def import_csv(table_name, csv_file):
    """Importe un CSV via \copy dans le pod."""
    cmd = f"kubectl exec {POD_NAME} -n {NAMESPACE} -- bash -c \"PGPASSWORD='{DB_PASSWORD}' psql -U {DB_USER} -d {DB_NAME} -c \\\"\\\\copy {table_name} FROM '{CSV_DIR}/{csv_file}' DELIMITER ',' CSV HEADER;\\\"\""
    return run_command(cmd)

def main():
    # Suppression des tables existantes (optionnel)
    drop_tables()

    # Création des tables
    if not create_tables():
        print("⚠️  Arrêt du script en raison d'une erreur.")
        return

    # Import des CSV
    print("\n📤 Import des données depuis les fichiers CSV...")
    for table_name, csv_file in CSV_FILES.items():
        if not import_csv(table_name, csv_file):
            print(f"⚠️  Échec de l'import pour '{table_name}'.")

    # Vérification
    print("\n📊 Vérification des données importées:")
    for table_name in TABLES.keys():
        cmd = f"kubectl exec {POD_NAME} -n {NAMESPACE} -- bash -c \"PGPASSWORD='{DB_PASSWORD}' psql -U {DB_USER} -d {DB_NAME} -c \\\"SELECT COUNT(*) FROM {table_name};\\\"\""
        run_command(cmd)

if __name__ == "__main__":
    main()
