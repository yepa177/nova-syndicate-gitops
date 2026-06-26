#!/bin/bash

# ================= CONFIGURATION =================
PROJECT_DIR="$HOME/nova-syndicate-gitops"   # ton dossier à sauvegarder
BACKUP_DIR="$HOME/backups"
DATE=$(date +"%Y-%m-%d_%H-%M")
BACKUP_FILE="$BACKUP_DIR/nova-backup_$DATE.tar.gz"
# ================================================

echo "=== Backup Nova Syndicate - $DATE ==="

# Créer le dossier backups s'il n'existe pas
mkdir -p "$BACKUP_DIR"

# ================= VÉRIFICATIONS DE SÉCURITÉ =================

# 1. Vérifier que le dossier projet existe
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERREUR: Le dossier $PROJECT_DIR n'existe pas !" >&2
    exit 3
fi

# 2. Vérifier l'espace disque disponible
echo "Vérification de l'espace disque..."

# Taille estimée du projet (en Ko)
PROJECT_SIZE_KB=$(du -sk "$PROJECT_DIR" 2>/dev/null | cut -f1)
if [ -z "$PROJECT_SIZE_KB" ]; then
    echo "ERREUR: Impossible de calculer la taille du projet" >&2
    exit 3
fi

# Espace disponible sur le disque où se trouve le dossier de backup (en Ko)
AVAILABLE_KB=$(df -Pk "$BACKUP_DIR" 2>/dev/null | tail -1 | awk '{print $4}')

# On veut au moins 50% d'espace en plus (marge de sécurité)
REQUIRED_KB=$((PROJECT_SIZE_KB * 150 / 100))

echo "Taille du projet     : $(numfmt --to=iec $((PROJECT_SIZE_KB * 1024)))"
echo "Espace disponible   : $(numfmt --to=iec $((AVAILABLE_KB * 1024)))"
echo "Espace requis (avec marge) : $(numfmt --to=iec $((REQUIRED_KB * 1024)))"

if [ "$AVAILABLE_KB" -lt "$REQUIRED_KB" ]; then
    echo "ERREUR: Pas assez d'espace disque !" >&2
    echo "Il manque environ $(numfmt --to=iec $(((REQUIRED_KB - AVAILABLE_KB) * 1024)))" >&2
    exit 4   # Code POSIX = espace insuffisant
fi

echo "✅ Espace disque suffisant"


# ===================== Faire le backup ================================

echo "Compression en cours..."
tar -czf "$BACKUP_FILE" -C "$HOME" nova-syndicate-gitops

# Vérifier si le backup a réussi
if [ $? -eq 0 ]; then
    echo "✅ Backup réussi : $BACKUP_FILE"
    echo "Taille : $(du -h "$BACKUP_FILE" | cut -f1)"
else
    echo "❌ Erreur pendant la compression"
    exit 1
fi

# Garder seulement les 7 derniers backups (supprime les plus anciens)
echo "Nettoyage des anciens backups..."
cd "$BACKUP_DIR" || exit
ls -t nova-backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -I {} rm -- "{}" 2>/dev/null

echo "=== Backup terminé ==="