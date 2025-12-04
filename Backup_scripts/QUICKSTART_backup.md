╔════════════════════════════════════════════════════════════════════════════╗
║            🚀 GUIDE INSTALLATION RAPIDE - BACKUP SERVEUR 2019              ║
╚════════════════════════════════════════════════════════════════════════════╝

📦 FICHIERS FOURNIS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Script_Backup_LOCAL_NAS.ps1     → Script principal de sauvegarde
2. Schedule_Backup_Tasks.ps1        → Planification automatique
3. Test_Backup_Connection.ps1       → Tests et diagnostics
4. BACKUP_GUIDE.md                  → Guide complet (documentation)
5. QUICKSTART.md                    → Ce fichier (installation rapide)


🎯 INSTALLATION EN 5 MINUTES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⏱️ ÉTAPE 1 - Créer les dossiers (30 secondes)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ouvrir PowerShell EN TANT QU'ADMINISTRATEUR et copier:

    New-Item -Path "C:\Scripts" -ItemType Directory -Force
    New-Item -Path "C:\Backups" -ItemType Directory -Force

✓ Dossiers créés


⏱️ ÉTAPE 2 - Copier les scripts (1 minute)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Copier les 3 fichiers PowerShell vers C:\Scripts:

    • Script_Backup_LOCAL_NAS.ps1
    • Schedule_Backup_Tasks.ps1
    • Test_Backup_Connection.ps1

✓ Fichiers copiés


⏱️ ÉTAPE 3 - Configurer les identifiants NAS (1 minute)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Éditer: C:\Scripts\Script_Backup_LOCAL_NAS.ps1

Chercher cette section (vers la ligne 20):

    # --- Chemins de sauvegarde ---
    $LocalBackupPath = "C:\Backups"
    $NASBackupPath = "\\192.168.2.199\VOTRESITE"
    $NASUsername = "VOTRESITE\Agence8"  ← À REMPLACER par votre nom d'agence
    $NASPassword = "Test123*"             ← À REMPLACER par votre mot de passe NAS

Adapter:
    • VOTRESITE → Remplacer par votre nom d'agence (ex: "MONS", "BRUXELLES", etc.)
    • Test123* → Remplacer par votre mot de passe NAS

💾 Sauvegarder le fichier

✓ Configuration adaptée


⏱️ ÉTAPE 4 - Tester (1 minute 30)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

En PowerShell ADMIN, exécuter le test:

    & "C:\Scripts\Test_Backup_Connection.ps1"

Attendre et vérifier les résultats:
    ✓ Si connectivité NAS = OK, continuer
    ❌ Si erreur = Vérifier identifiants et pare-feu (voir TROUBLESHOOTING plus bas)

✓ Configuration validée


⏱️ ÉTAPE 5 - Planifier les sauvegardes (1 minute)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

En PowerShell ADMIN, exécuter:

    & "C:\Scripts\Schedule_Backup_Tasks.ps1"

Cela créera 3 tâches:
    📅 Backup-Daily-2AM          → Chaque jour à 2h
    📅 Backup-Weekly-Sunday-1AM  → Chaque dimanche à 1h
    🧹 Cleanup-OldBackupLogs     → Dimanche à 3h

✓ Installation terminée !


🧪 TESTER MANUELLEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Avant de faire confiance à l'automatisation, tester une sauvegarde:

    & "C:\Scripts\Script_Backup_LOCAL_NAS.ps1"

Vérifier les résultats:
    • Affichage console (messages verts = OK)
    • Fichiers dans C:\Backups
    • Fichiers dans \\192.168.2.199\VOTRESITE\
    • Logs dans C:\Backups\Logs\*.log

⚠️  Important: Ne planifier les tâches que si ce test réussit!


📊 VÉRIFIER LES SAUVEGARDES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Après le test ou après la première sauvegarde automatique:

1. Vérifier les fichiers locaux:
   Dossier: C:\Backups\
   Commande: Get-ChildItem -Path "C:\Backups" -Recurse | Measure-Object -Sum

2. Vérifier sur le NAS:
   Dossier: \\192.168.2.199\VOTRESITE\[NomServeur]\

3. Vérifier les logs:
   Commande: Get-ChildItem -Path "C:\Backups\Logs" -Filter "*.log" | Select -Last 5
   Commande: Get-Content "C:\Backups\Logs\Backup_*.log" | Select -Last 50


❌ TROUBLESHOOTING RAPIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ Erreur: "Accès refusé au NAS"
   ✓ Vérifier identifiants NAS (Script ligne 20-25)
   ✓ Vérifier format: "VOTRESITE\Agence8" (pas juste "Agence8")
   ✓ Vérifier pare-feu: Le port 445 doit être ouvert
   ✓ Tester manuellement: net use \\192.168.2.199\VOTRESITE /user:VOTRESITE\Agence8 Test123*

❌ Erreur: "Dossier introuvable C:\Backups"
   ✓ Créer manuellement: New-Item -Path "C:\Backups" -ItemType Directory -Force

❌ Erreur: "Tâche planifiée ne s'exécute pas"
   ✓ Vérifier le statut: Get-ScheduledTask -TaskName "Backup-Daily-2AM"
   ✓ Vérifier le chemin du script: Doit être C:\Scripts\Script_Backup_LOCAL_NAS.ps1
   ✓ Tester manuellement: Start-ScheduledTask -TaskName "Backup-Daily-2AM"

❌ Sauvegarde très lente
   ✓ Vérifier la bande passante réseau (tester ping)
   ✓ Décaler l'horaire à 3h du matin au lieu de 2h
   ✓ Exclure certains dossiers non critiques


🔧 COMMANDES UTILES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Afficher les tâches planifiées:
    Get-ScheduledTask -TaskName "Backup-*"

Tester une sauvegarde manuelle:
    & "C:\Scripts\Script_Backup_LOCAL_NAS.ps1"

Consulter les logs:
    Get-Content "C:\Backups\Logs\Backup_*.log" -Tail 50

Vérifier l'espace utilisé:
    (Get-ChildItem -Path "C:\Backups" -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB

Tester connexion NAS:
    Test-Path "\\192.168.2.199\VOTRESITE" -Credential (Get-Credential)


📞 BESOIN D'AIDE ?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Consulter: BACKUP_GUIDE.md (documentation complète)

Points clés:
    • Section "Configuration avancée" pour adapter les horaires
    • Section "Troubleshooting" pour les erreurs courantes
    • Section "Monitoring" pour superviser les sauvegardes


✅ CHECKLIST - Confirmer avant de partir
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    ☐ Dossiers C:\Scripts et C:\Backups créés
    ☐ 3 scripts PowerShell copiés
    ☐ Identifiants NAS adaptés dans Script_Backup_LOCAL_NAS.ps1
    ☐ Test_Backup_Connection.ps1 exécuté avec succès
    ☐ Sauvegarde manuelle testée (Script_Backup_LOCAL_NAS.ps1)
    ☐ Fichiers créés dans C:\Backups
    ☐ Fichiers créés dans \\192.168.2.199\VOTRESITE
    ☐ Tâches planifiées créées (Schedule_Backup_Tasks.ps1)
    ☐ Tâches visibles dans l'Observateur de tâches planifiées
    ☐ Logs consultés et OK

Tous les ☐ cochés → Vous êtes bon ! 🎉


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✨ Installation maintenant terminée !

Les sauvegardes s'exécuteront automatiquement:
    ✓ Chaque jour à 2h du matin
    ✓ Chaque dimanche à 1h du matin
    ✓ Sauvegarde locale: C:\Backups
    ✓ Sauvegarde NAS: \\192.168.2.199\VOTRESITE

Consulter les logs pour vérifier le bon déroulement:
    C:\Backups\Logs\*.log

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
