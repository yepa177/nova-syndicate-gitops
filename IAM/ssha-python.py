import base64
import hashlib
import os

def check_ssha(password, ssha_hash):
    # Enlever le préfixe {SSHA}
    hash_data = base64.b64decode(ssha_hash.replace('{SSHA}', ''))
    salt = hash_data[20:]  # Les 20 premiers octets = hash SHA-1
    hash_part = hash_data[:20]
    
    # Hasher le mot de passe avec le même salt
    test_hash = hashlib.sha1(password.encode() + salt).digest()
    
    return test_hash == hash_part

# Test
hash_ssha = "UW2kWjZfZvT+L5aElUYr/3FvLLM6zYnW"
print(check_ssha('DevP@ssw0rd2026!', hash_ssha))  # True ou False
