#!/usr/bin/env python3
import psycopg2
import os
from psycopg2 import sql
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

# Configuration de la connexion à PostgreSQL
DB_NAME = "nova_syndicate"
DB_USER = "yepa177"
DB_PASSWORD = "qwerty123"  # Remplace par ton mot de passe
DB_HOST = "localhost"
DB_PORT = "5432"
CSV_DIR = "/home/user/nova-syndicate-gitops/nova-syndicate-csv"  # Répertoire où se trouvent les fichiers CSV dans le pod (ou localement)

# Tables et leurs schémas
TABLES = {
    "collaborateurs": """
        CREATE TABLE collaborateurs (
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
        CREATE TABLE clients (
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
        CREATE TABLE produits_medicaux (
            id_produit SERIAL PRIMARY KEY,
            nom_produit VARCHAR(100),
            description TEXT,
            prix_unitaire DECIMAL(10, 2),
            stock INT
        );
    """,
    "produits_aerospatiaux": """
        CREATE TABLE produits_aerospatiaux (
            id_produit SERIAL PRIMARY KEY,
            nom_produit VARCHAR(100),
            description TEXT,
            prix_unitaire DECIMAL(10, 2),
            stock INT
        );
    """,
    "commandes": """
        CREATE TABLE commandes (
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

def create_tables(conn):
    """Crée les tables dans la base de données."""
    with conn.cursor() as cursor:
        for table_name, create_sql in TABLES.items():
            try:
                cursor.execute(create_sql)
                print(f"✅ Table '{table_name}' créée avec succès.")
            except psycopg2.Error as e:
                print(f"❌ Erreur lors de la création de la table '{table_name}': {e}")
                conn.rollback()
                return False
    conn.commit()
    return True

def import_csv(conn, table_name, csv_file_path):
    """Importe les données depuis un fichier CSV vers une table."""
    try:
        with conn.cursor() as cursor:
            with open(csv_file_path, "r") as f:
                cursor.copy_expert(
                    sql.SQL("COPY {} FROM STDIN WITH CSV HEADER").format(sql.Identifier(table_name)),
                    f
                )
            print(f"✅ Données importées dans '{table_name}' depuis '{csv_file_path}'.")
    except psycopg2.Error as e:
        print(f"❌ Erreur lors de l'import des données pour '{table_name}': {e}")
        conn.rollback()
        return False
    conn.commit()
    return True

def main():
    # Connexion à PostgreSQL
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        print(f"🔌 Connexion à la base de données '{DB_NAME}' établie.")
    except psycopg2.Error as e:
        print(f"❌ Impossible de se connecter à la base de données: {e}")
        return

    # Création des tables
    print("\n🛠️ Création des tables...")
    if not create_tables(conn):
        print("⚠️ Arrêt du script en raison d'une erreur.")
        return

    # Import des données depuis les fichiers CSV
    print("\n📤 Import des données depuis les fichiers CSV...")
    for table_name, csv_file in CSV_FILES.items():
        csv_path = os.path.join(CSV_DIR, csv_file)
        if not os.path.exists(csv_path):
            print(f"⚠️ Le fichier '{csv_path}' n'existe pas. Import annulé pour '{table_name}'.")
            continue
        if not import_csv(conn, table_name, csv_path):
            print(f"⚠️ Échec de l'import pour '{table_name}'.")

    # Vérification des données importées
    print("\n📊 Vérification des données importées:")
    with conn.cursor() as cursor:
        for table_name in TABLES.keys():
            cursor.execute(sql.SQL("SELECT COUNT(*) FROM {}").format(sql.Identifier(table_name)))
            count = cursor.fetchone()[0]
            print(f"  - {table_name}: {count} lignes")

    conn.close()
    print("\n🎉 Script terminé avec succès!")

if __name__ == "__main__":
    main()
