#!/bin/bash
#####################################################################
# Script de déploiement Multi-TAC CMAS
# F2G TelcoLab - Effet de zone géographique
#
# Usage:
#   ./deploy_multi_tac.sh setup    # Configuration initiale
#   ./deploy_multi_tac.sh start    # Démarrer PC1 (Core + eNB1)
#   ./deploy_multi_tac.sh pc2      # Préparer les fichiers pour PC2
#   ./deploy_multi_tac.sh test     # Tester la connectivité
#####################################################################

set -e

# Configuration
PC1_IP="192.168.1.100"
PC2_IP="192.168.1.101"
DOCKER_COMPOSE_FILE="4g-volte-deploy.yaml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           F2G Multi-TAC CMAS - Effet de Zone                  ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  PC1 (TAC 1): Core + eNB1 - Zone Yaoundé - CMAS ACTIVÉ       ║"
    echo "║  PC2 (TAC 2): eNB2 seul   - Zone Douala  - PAS DE CMAS       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

setup() {
    echo -e "${YELLOW}[SETUP] Configuration du système Multi-TAC...${NC}"
    
    # Sauvegarder l'ancienne config MME
    if [ -f "mme/mme.yaml.backup" ]; then
        echo "Backup MME existe déjà"
    else
        cp mme/mme.yaml mme/mme.yaml.backup
        echo -e "${GREEN}✓ Backup créé: mme/mme.yaml.backup${NC}"
    fi
    
    # Copier la nouvelle config MME multi-TAC
    cp mme/mme-multi-tac.yaml mme/mme.yaml
    echo -e "${GREEN}✓ Config MME multi-TAC activée${NC}"
    
    # Vérifier les fichiers eNB
    echo ""
    echo -e "${BLUE}Fichiers créés:${NC}"
    ls -la srsran/*.conf | grep -E "tac[12]"
    
    echo ""
    echo -e "${GREEN}[SETUP] Configuration terminée!${NC}"
    echo ""
    echo -e "${YELLOW}Prochaines étapes:${NC}"
    echo "1. Sur PC1: $0 start"
    echo "2. Sur PC2: Copier les fichiers avec $0 pc2"
}

start_pc1() {
    echo -e "${YELLOW}[START] Démarrage du Core + eNB1 sur PC1...${NC}"
    
    # Arrêter l'ancien déploiement
    echo "Arrêt des containers..."
    docker-compose -f $DOCKER_COMPOSE_FILE down 2>/dev/null || true
    
    # Démarrer le nouveau déploiement
    echo "Démarrage des containers..."
    docker-compose -f $DOCKER_COMPOSE_FILE up -d
    
    # Attendre que le MME soit prêt
    echo "Attente du MME..."
    sleep 10
    
    # Vérifier le MME
    echo ""
    echo -e "${BLUE}[INFO] Vérification du MME...${NC}"
    docker logs mme 2>&1 | tail -20
    
    echo ""
    echo -e "${GREEN}[START] Core démarré!${NC}"
    echo ""
    echo -e "${YELLOW}Pour démarrer eNB1 (TAC 1 avec CMAS):${NC}"
    echo "  sudo srsenb srsran/enb_tac1_cmas.conf"
    echo ""
    echo -e "${YELLOW}Ou pour utiliser l'ancienne config:${NC}"
    echo "  sudo srsenb srsran/enb_pws.conf"
}

prepare_pc2() {
    echo -e "${YELLOW}[PC2] Préparation des fichiers pour PC2...${NC}"
    
    # Créer un dossier avec les fichiers à copier
    PC2_DIR="/tmp/pc2_enb_config"
    rm -rf $PC2_DIR
    mkdir -p $PC2_DIR
    
    # Copier les fichiers
    cp srsran/enb_tac2_no_cmas.conf $PC2_DIR/
    cp srsran/sib_tac2_no_cmas.conf $PC2_DIR/
    
    # Créer un README pour PC2
    cat > $PC2_DIR/README_PC2.txt << 'EOF'
═══════════════════════════════════════════════════════════════════
 F2G Multi-TAC CMAS - Configuration PC2 (eNB2 - Zone Douala)
═══════════════════════════════════════════════════════════════════

ÉTAPES D'INSTALLATION SUR PC2:
------------------------------

1. COPIER CES FICHIERS:
   scp -r /tmp/pc2_enb_config/* user@PC2:/home/user/srsran/

2. MODIFIER enb_tac2_no_cmas.conf:
   - Changer gtp_bind_addr = VOTRE_IP_PC2
   - Changer s1c_bind_addr = VOTRE_IP_PC2
   - Vérifier mme_addr = 192.168.1.155 (IP du PC1)

3. VÉRIFIER LA CONNECTIVITÉ:
   ping 192.168.1.155
   nc -zv 192.168.1.155 36412

4. DÉMARRER eNB2:
   sudo srsenb /home/user/srsran/enb_tac2_no_cmas.conf

5. TEST:
   - Téléphone proche de PC2 → Se connecte à TAC 2
   - N'affichera PAS les alertes CMAS envoyées sur TAC 1
EOF
    
    echo ""
    echo -e "${GREEN}[PC2] Fichiers préparés dans: $PC2_DIR${NC}"
    echo ""
    ls -la $PC2_DIR/
    echo ""
    echo -e "${YELLOW}Pour copier vers PC2:${NC}"
    echo "  scp -r $PC2_DIR/* user@$PC2_IP:/home/user/srsran/"
    echo ""
    echo -e "${YELLOW}Ou copier manuellement via clé USB.${NC}"
}

test_connectivity() {
    echo -e "${YELLOW}[TEST] Test de connectivité...${NC}"
    echo ""
    
    # Test ping PC2
    echo -e "${BLUE}Ping vers PC2 ($PC2_IP):${NC}"
    if ping -c 3 $PC2_IP > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PC2 accessible${NC}"
    else
        echo -e "${RED}✗ PC2 non accessible - Vérifier le câble Ethernet${NC}"
    fi
    
    # Test Docker
    echo ""
    echo -e "${BLUE}État des containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | head -10
    
    # Test MME
    echo ""
    echo -e "${BLUE}Test port S1AP (36412):${NC}"
    if ss -tlnp | grep -q 36412; then
        echo -e "${GREEN}✓ MME écoute sur port 36412${NC}"
    else
        echo -e "${RED}✗ Port 36412 non ouvert${NC}"
    fi
    
    # Afficher IPs
    echo ""
    echo -e "${BLUE}Interfaces réseau:${NC}"
    ip -4 addr show | grep -E "inet " | grep -v "127.0.0.1"
}

show_status() {
    echo -e "${BLUE}[STATUS] État du système${NC}"
    echo ""
    
    echo "=== CONTAINERS ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "mme|hss|sgw|smf|upf|mongo" || echo "Aucun container actif"
    
    echo ""
    echo "=== CONFIGURATION ==="
    echo "MME Config: $(ls -la mme/mme.yaml | awk '{print $NF}')"
    echo "eNB1 Config: srsran/enb_tac1_cmas.conf"
    echo "eNB2 Config: srsran/enb_tac2_no_cmas.conf"
    
    echo ""
    echo "=== RÉSEAU ==="
    echo "PC1 IP: $PC1_IP"
    echo "PC2 IP: $PC2_IP"
}

send_alert() {
    ALERT_TYPE=${1:-presidential}
    MESSAGE=${2:-"Test alerte zone TAC 1 uniquement"}
    
    echo -e "${YELLOW}[ALERT] Envoi alerte CMAS sur TAC 1...${NC}"
    echo "Type: $ALERT_TYPE"
    echo "Message: $MESSAGE"
    
    if [ -f "scripts/send_pws_alert.sh" ]; then
        ./scripts/send_pws_alert.sh $ALERT_TYPE "$MESSAGE"
    else
        echo -e "${RED}Script send_pws_alert.sh non trouvé${NC}"
    fi
}

# Main
print_banner

case "$1" in
    setup)
        setup
        ;;
    start)
        start_pc1
        ;;
    pc2)
        prepare_pc2
        ;;
    test)
        test_connectivity
        ;;
    status)
        show_status
        ;;
    alert)
        send_alert "$2" "$3"
        ;;
    restore)
        echo "Restauration de l'ancienne config MME..."
        cp mme/mme.yaml.backup mme/mme.yaml
        echo -e "${GREEN}Config restaurée${NC}"
        ;;
    *)
        echo "Usage: $0 {setup|start|pc2|test|status|alert|restore}"
        echo ""
        echo "  setup   - Configuration initiale multi-TAC"
        echo "  start   - Démarrer Core + eNB1 sur PC1"
        echo "  pc2     - Préparer les fichiers pour PC2"
        echo "  test    - Tester la connectivité"
        echo "  status  - Afficher l'état du système"
        echo "  alert   - Envoyer une alerte (ex: $0 alert presidential 'Message')"
        echo "  restore - Restaurer l'ancienne config MME"
        exit 1
        ;;
esac
