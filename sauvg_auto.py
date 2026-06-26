#!/usr/bin/env python3
"""
Script de backup automatique pour Nova Syndicate
Version complète - Bien commentée et robuste
"""

import os
import tarfile
import datetime
import sys
import shutil
from pathlib import Path


# ===================== CONFIGURATION =====================

# Nom du dossier à sauvegarder
PROJECT_NAME = "nova-syndicate-gitops"

# Chemins complets
PROJECT_DIR = Path.home() / PROJECT_NAME          # ~/nova-syndicate-gitops
BACKUP_DIR = Path.home() / "backups"              # ~/backups

# Nombre de backups à conserver (7 = une semaine si backup quotidien)
KEEP_BACKUPS = 7

# ========================================================


def check_requirements():
    """Vérifie que le projet existe et prépare le dossier de backup"""
    print("🔍 Vérification des prérequis...")

    if not PROJECT_DIR.exists():
        print(f"❌ ERREUR: Le dossier projet {PROJECT_DIR} n'existe pas !")
        sys.exit(3)  # Code 3 = ressource manquante

    # Création du dossier backups s'il n'existe pas
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    print(f"✅ Projet trouvé : {PROJECT_DIR}")
    print(f"✅ Dossier backup : {BACKUP_DIR}")


def check_disk_space():
    """Vérifie qu'il y a assez d'espace disque (avec marge de sécurité)"""
    print("\n📊 Vérification de l'espace disque...")

    # Calcul de la taille réelle du projet
    total_size = 0
    for path in PROJECT_DIR.rglob('*'):
        if path.is_file():
            total_size += path.stat().st_size

    project_size_gb = total_size / (1024 ** 3)
    disk = shutil.disk_usage(BACKUP_DIR)
    free_gb = disk.free / (1024 ** 3)

    print(f"Taille du projet      : {project_size_gb:.2f} GB")
    print(f"Espace disponible     : {free_gb:.2f} GB")

    # On demande 2x la taille du projet en espace libre (marge de sécurité)
    if free_gb < (project_size_gb * 2):
        print("❌ ERREUR: Pas assez d'espace disque !")
        print(f"   Il faut au moins {project_size_gb * 2:.2f} GB libres.")
        sys.exit(4)  # Code 4 = espace insuffisant

    print("✅ Espace disque suffisant")


def create_backup():
    """Crée le fichier de backup compressé (.tar.gz)"""
    date_str = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M")
    backup_filename = f"nova-backup_{date_str}.tar.gz"
    backup_path = BACKUP_DIR / backup_filename

    print(f"\n📦 Création du backup → {backup_filename}")

    try:
        with tarfile.open(backup_path, "w:gz") as tar:
            tar.add(PROJECT_DIR, arcname=PROJECT_NAME)

        size_mb = backup_path.stat().st_size / (1024 ** 2)
        print(f"✅ Backup créé avec succès ! Taille : {size_mb:.1f} MB")
        return backup_path

    except Exception as e:
        print(f"❌ Erreur pendant la création du backup : {e}")
        sys.exit(5)


def cleanup_old_backups():
    """Supprime les anciens backups et garde seulement les plus récents"""
    print(f"\n🧹 Nettoyage : conservation des {KEEP_BACKUPS} derniers backups...")

    # Liste tous les backups et les trie du plus récent au plus ancien
    backups = sorted(
        BACKUP_DIR.glob("nova-backup_*.tar.gz"),
        key=os.path.getmtime,
        reverse=True
    )

    if len(backups) <= KEEP_BACKUPS:
        print("   Aucun backup à supprimer.")
        return

    to_delete = backups[KEEP_BACKUPS:]

    for old_backup in to_delete:
        old_backup.unlink()
        print(f"   🗑️  Supprimé : {old_backup.name}")


# ===================== PROGRAMME PRINCIPAL =====================

if __name__ == "__main__":
    print("=" * 65)
    print("🚀 BACKUP AUTOMATIQUE NOVA SYNDICATE")
    print("=" * 65)

    check_requirements()
    check_disk_space()
    create_backup()
    cleanup_old_backups()

    print("\n🎉 Tout s'est bien passé ! Backup terminé.")
    print("=" * 65)