#!/usr/bin/env python3
"""
Vérificateur de mots de passe SSHA - Version avec gestion du double encodage
"""

import base64
import hashlib
import sys
import re

try:
    from ldap3 import Server, Connection, ALL
except ImportError:
    print("❌ ldap3 non installé. Exécutez: pip install ldap3")
    sys.exit(1)

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

class SSHAValidator:
    @staticmethod
    def decode_password_field(raw_value) -> str:
        """
        Décode intelligemment un champ userPassword qui peut être :
        - Un hash SSHA simple: {SSHA}xxxxx
        - Un hash encodé en Base64: e1NTSEF9...
        - Un double encodage
        """
        # Si c'est un objet bytes, le décoder
        if isinstance(raw_value, bytes):
            raw_value = raw_value.decode('utf-8')
        
        raw_value = str(raw_value).strip()
        
        print(f"📝 Valeur brute reçue: {raw_value[:30]}...")
        
        # Si c'est déjà un hash SSHA, le renvoyer tel quel
        if raw_value.startswith('{SSHA}'):
            print(f"   → Déjà un hash SSHA")
            return raw_value
        
        # Essayer de décoder du Base64 qui contient {SSHA}
        try:
            decoded = base64.b64decode(raw_value).decode('utf-8')
            print(f"   → Décodage Base64: {decoded[:30]}...")
            if decoded.startswith('{SSHA}'):
                print(f"   ✅ Hash SSHA extrait du Base64")
                return decoded
            # Si décodé mais pas {SSHA}, c'est peut-être un hash sans préfixe
            if len(decoded) >= 20:
                return f"{{SSHA}}{decoded}"
        except Exception as e:
            print(f"   → Pas un Base64 valide: {e}")
        
        # Si ça ressemble à un hash Base64 sans préfixe
        if re.match(r'^[A-Za-z0-9+/]+=*$', raw_value):
            try:
                # Tester si ça se décode en quelque chose
                decoded = base64.b64decode(raw_value)
                if len(decoded) > 20:
                    return f"{{SSHA}}{raw_value}"
            except:
                pass
        
        # Si c'est un hash SSHA sans le préfixe
        if len(raw_value) >= 28 and re.match(r'^[A-Za-z0-9+/]+=*$', raw_value):
            return f"{{SSHA}}{raw_value}"
        
        # Dernier recours : le hash est peut-être déjà le bon mais mal formaté
        print(f"   ⚠️  Format non reconnu, tentative de correction...")
        return raw_value
    
    @staticmethod
    def verify_ssha_password(password: str, raw_hash: str) -> bool:
        """
        Vérifie un mot de passe contre un hash SSHA
        """
        # Extraire le hash correct
        ssha_hash = SSHAValidator.decode_password_field(raw_hash)
        
        # Enlever le préfixe {SSHA} si présent
        if ssha_hash.startswith('{SSHA}'):
            ssha_hash = ssha_hash[6:]
        
        # Nettoyer
        ssha_hash = ssha_hash.strip()
        
        print(f"🔐 Hash extrait: {ssha_hash[:20]}... (longueur: {len(ssha_hash)})")
        
        try:
            # Décoder le Base64
            hash_bytes = base64.b64decode(ssha_hash)
            
            print(f"   ✅ Décodage réussi: {len(hash_bytes)} octets")
            
            if len(hash_bytes) <= 20:
                print(f"   ❌ Hash trop court: {len(hash_bytes)} octets")
                return False
            
            sha1_hash = hash_bytes[:20]
            salt = hash_bytes[20:]
            
            print(f"   SHA-1: {sha1_hash.hex()[:16]}...")
            print(f"   Salt: {salt.hex()[:16]}...")
            
            # Calculer le hash de test
            test_hash = hashlib.sha1(password.encode('utf-8') + salt).digest()
            
            result = test_hash == sha1_hash
            print(f"   {'✅' if result else '❌'} Vérification: {'Correct' if result else 'Incorrect'}")
            
            return result
            
        except Exception as e:
            print(f"❌ Erreur de décodage: {e}")
            
            # Tentative de correction : peut-être que le hash a été encodé 2 fois
            try:
                print(f"   🔄 Tentative de décodage supplémentaire...")
                # Si le hash est en Base64, le décoder
                decoded = base64.b64decode(ssha_hash).decode('utf-8')
                if decoded.startswith('{SSHA}'):
                    return SSHAValidator.verify_ssha_password(password, decoded)
            except:
                pass
            
            return False

def main():
    print(f"""
{Colors.BOLD}{Colors.CYAN}╔════════════════════════════════════════════════════════╗
║   🔐 VÉRIFICATEUR SSHA - Double encodage géré          ║
╚════════════════════════════════════════════════════════╝{Colors.RESET}
    """)
    
    # 🔧 Configuration
    LDAP_HOST = '10.96.253.34'
    LDAP_PORT = 389
    LDAP_USER = 'cn=admin,dc=assurance,dc=local'
    LDAP_PASS = 'ComplexP@ssw0rd2026!'
    LDAP_BASE = 'dc=assurance,dc=local'
    
    validator = SSHAValidator()
    
    while True:
        print(f"\n{Colors.BOLD}Options:{Colors.RESET}")
        print("  1. Vérifier un utilisateur")
        print("  2. Vérifier un hash directement")
        print("  3. Tester la connexion LDAP")
        print("  4. Voir le hash d'un utilisateur")
        print("  5. Mode debug (affiche tout)")
        print("  0. Quitter")
        
        choice = input(f"\n{Colors.BOLD}Votre choix: {Colors.RESET}").strip()
        
        if choice == '0':
            print(f"{Colors.GREEN}👋 Au revoir!{Colors.RESET}")
            break
        
        elif choice == '1':
            uid = input(f"{Colors.BOLD}UID de l'utilisateur: {Colors.RESET}").strip()
            if not uid:
                continue
            
            password = input(f"{Colors.BOLD}Mot de passe à vérifier: {Colors.RESET}").strip()
            if not password:
                continue
            
            print(f"\n{Colors.BLUE}🔍 Connexion à {LDAP_HOST}:{LDAP_PORT}...{Colors.RESET}")
            
            try:
                server = Server(LDAP_HOST, port=LDAP_PORT, get_info=ALL)
                conn = Connection(server, user=LDAP_USER, password=LDAP_PASS)
                
                if not conn.bind():
                    print(f"{Colors.RED}❌ Échec de connexion: {conn.last_error}{Colors.RESET}")
                    continue
                
                print(f"{Colors.GREEN}✅ Connexion réussie{Colors.RESET}")
                
                conn.search(
                    search_base=LDAP_BASE,
                    search_filter=f"(uid={uid})",
                    attributes=['uid', 'cn', 'userPassword']
                )
                
                if len(conn.entries) == 0:
                    print(f"{Colors.RED}❌ Utilisateur {uid} non trouvé{Colors.RESET}")
                    conn.unbind()
                    continue
                
                entry = conn.entries[0]
                
                if 'userPassword' not in entry:
                    print(f"{Colors.RED}❌ Pas de mot de passe stocké pour {uid}{Colors.RESET}")
                    conn.unbind()
                    continue
                
                # Récupérer le(s) hash(s)
                if hasattr(entry['userPassword'], 'values'):
                    passwords = entry['userPassword'].values
                else:
                    passwords = [str(entry['userPassword'])]
                
                print(f"🔐 Vérification du mot de passe...")
                found = False
                
                for stored in passwords:
                    stored_str = str(stored)
                    print(f"\n{Colors.CYAN}--- Hash #{passwords.index(stored)+1} ---{Colors.RESET}")
                    if validator.verify_ssha_password(password, stored_str):
                        print(f"{Colors.GREEN}✅ Mot de passe CORRECT pour {uid}{Colors.RESET}")
                        found = True
                        break
                
                if not found:
                    print(f"{Colors.RED}❌ Mot de passe INCORRECT pour {uid}{Colors.RESET}")
                
                conn.unbind()
                
            except Exception as e:
                print(f"{Colors.RED}❌ Erreur: {e}{Colors.RESET}")
        
        elif choice == '2':
            password = input(f"{Colors.BOLD}Mot de passe: {Colors.RESET}").strip()
            ssha_hash = input(f"{Colors.BOLD}Hash SSHA: {Colors.RESET}").strip()
            
            if validator.verify_ssha_password(password, ssha_hash):
                print(f"{Colors.GREEN}✅ Hash valide!{Colors.RESET}")
            else:
                print(f"{Colors.RED}❌ Hash invalide!{Colors.RESET}")
        
        elif choice == '3':
            print(f"\n{Colors.BLUE}🔍 Test de connexion à {LDAP_HOST}:{LDAP_PORT}...{Colors.RESET}")
            try:
                server = Server(LDAP_HOST, port=LDAP_PORT, get_info=ALL)
                conn = Connection(server, user=LDAP_USER, password=LDAP_PASS)
                
                if conn.bind():
                    print(f"{Colors.GREEN}✅ Connexion réussie à {LDAP_HOST}:{LDAP_PORT}{Colors.RESET}")
                    conn.unbind()
                else:
                    print(f"{Colors.RED}❌ Échec: {conn.last_error}{Colors.RESET}")
            except Exception as e:
                print(f"{Colors.RED}❌ Erreur: {e}{Colors.RESET}")
        
        elif choice == '4':
            uid = input(f"{Colors.BOLD}UID de l'utilisateur: {Colors.RESET}").strip()
            if not uid:
                continue
            
            try:
                server = Server(LDAP_HOST, port=LDAP_PORT, get_info=ALL)
                conn = Connection(server, user=LDAP_USER, password=LDAP_PASS)
                
                if not conn.bind():
                    print(f"{Colors.RED}❌ Échec de connexion{Colors.RESET}")
                    continue
                
                conn.search(
                    search_base=LDAP_BASE,
                    search_filter=f"(uid={uid})",
                    attributes=['uid', 'userPassword']
                )
                
                if len(conn.entries) == 0:
                    print(f"{Colors.RED}❌ Utilisateur {uid} non trouvé{Colors.RESET}")
                else:
                    entry = conn.entries[0]
                    if 'userPassword' in entry:
                        if hasattr(entry['userPassword'], 'values'):
                            passwords = entry['userPassword'].values
                        else:
                            passwords = [str(entry['userPassword'])]
                        
                        print(f"\n{Colors.CYAN}Hashs stockés pour {uid}:{Colors.RESET}")
                        for i, pwd in enumerate(passwords):
                            print(f"  [{i+1}] {str(pwd)}")
                    else:
                        print(f"{Colors.YELLOW}⚠️  Pas de mot de passe stocké{Colors.RESET}")
                
                conn.unbind()
                
            except Exception as e:
                print(f"{Colors.RED}❌ Erreur: {e}{Colors.RESET}")
        
        elif choice == '5':
            print(f"\n{Colors.CYAN}🔧 Mode debug - Test direct du hash{Colors.RESET}")
            test_hash = "e1NTSEF9VVcya1dqWmZadlQrTDVhRWxVWXIvM0Z2TExNNnpZblc="
            test_password = "DevP@ssw0rd2026!"
            print(f"Hash test: {test_hash}")
            print(f"Password test: {test_password}")
            print("\nDécodage en plusieurs étapes:")
            
            # Étape 1: Décoder le Base64
            try:
                decoded = base64.b64decode(test_hash).decode('utf-8')
                print(f"  Étape 1 - Base64 décodé: {decoded}")
            except Exception as e:
                print(f"  Étape 1 - Erreur: {e}")
            
            # Étape 2: Vérifier le hash
            validator.verify_ssha_password(test_password, test_hash)
        
        else:
            print(f"{Colors.YELLOW}⚠️  Option invalide{Colors.RESET}")

if __name__ == "__main__":
    main()