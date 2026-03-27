#!/bin/bash
# Module: Generated Files Cleanup
# Step 6/6 of demo cleanup

cleanup_generated_files() {
  rm -f "$WARPSTREAM_AGENT_FILE"
  rm -f "${WARPSTREAM_AGENT_FILE}.backup."*
  echo -e "${GREEN}✓ Generated WarpStream agent manifest/backups removed${NC}"

  rm -f "$TABLEFLOW_PIPELINE_FILE"
  echo -e "${GREEN}✓ Generated Tableflow pipeline config removed${NC}"

  if [ "$TF_DESTROY_SUCCESS_WARPSTREAM" = true ] && [ -d "$WARPSTREAM_TF_DIR" ]; then
    rm -rf "${WARPSTREAM_TF_DIR}/.terraform"
    rm -f  "${WARPSTREAM_TF_DIR}/.terraform.lock.hcl"
    rm -f  "${WARPSTREAM_TF_DIR}/terraform.tfstate"
    rm -f  "${WARPSTREAM_TF_DIR}/terraform.tfstate.backup"
    echo -e "${GREEN}✓ WarpStream Terraform state removed${NC}"
  elif [ -d "$WARPSTREAM_TF_DIR" ]; then
    echo -e "${YELLOW}Keeping WarpStream Terraform state (destroy was not successful)${NC}"
  fi

  if [ "$TF_DESTROY_SUCCESS_AZURE" = true ] && [ -d "$AZURE_TF_DIR" ]; then
    rm -rf "${AZURE_TF_DIR}/.terraform"
    rm -f  "${AZURE_TF_DIR}/.terraform.lock.hcl"
    rm -f  "${AZURE_TF_DIR}/terraform.tfstate"
    rm -f  "${AZURE_TF_DIR}/terraform.tfstate.backup"
    echo -e "${GREEN}✓ Azure Terraform state removed${NC}"
  elif [ -d "$AZURE_TF_DIR" ]; then
    echo -e "${YELLOW}Keeping Azure Terraform state (destroy was not successful)${NC}"
  fi

  if [ "$TF_DESTROY_SUCCESS_TABLEFLOW_PIPELINE" = true ] && [ -d "$TABLEFLOW_PIPELINE_TF_DIR" ]; then
    rm -rf "${TABLEFLOW_PIPELINE_TF_DIR}/.terraform"
    rm -f  "${TABLEFLOW_PIPELINE_TF_DIR}/.terraform.lock.hcl"
    rm -f  "${TABLEFLOW_PIPELINE_TF_DIR}/terraform.tfstate"
    rm -f  "${TABLEFLOW_PIPELINE_TF_DIR}/terraform.tfstate.backup"
    echo -e "${GREEN}✓ Tableflow pipeline Terraform state removed${NC}"
  elif [ -d "$TABLEFLOW_PIPELINE_TF_DIR" ]; then
    echo -e "${YELLOW}Keeping Tableflow pipeline Terraform state (destroy was not successful)${NC}"
  fi
}

run_step_cleanup_files() {
  echo -e "${YELLOW}[6/6] Cleaning generated files...${NC}"
  cleanup_generated_files
}
