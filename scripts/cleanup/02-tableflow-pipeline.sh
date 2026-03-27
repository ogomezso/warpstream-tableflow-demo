#!/bin/bash
# Module: Tableflow Pipeline Destruction
# Step 2/6 of demo cleanup

run_step_destroy_tableflow_pipeline() {
  echo -e "${YELLOW}[2/6] Destroying Tableflow pipeline...${NC}"
  terraform_destroy_if_exists "$TABLEFLOW_PIPELINE_TF_DIR" "Tableflow Pipeline" || true
}
