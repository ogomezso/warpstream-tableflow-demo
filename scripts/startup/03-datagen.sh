#!/bin/bash
# Module: Datagen Connector Deployment
# Step 3/7 of demo startup

run_step_datagen() {
  echo -e "${YELLOW}[3/6] Deploying Datagen connector and topic...${NC}"
  kubectl apply -f "$DATAGEN_CONNECTOR_FILE"
  echo -e "${GREEN}✓ Datagen connector deployed${NC}\n"
}
