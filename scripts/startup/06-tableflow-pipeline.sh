#!/bin/bash
# Module: Tableflow Pipeline Creation
# Step 6/6 of demo startup

run_step_tableflow_pipeline() {
  echo -e "${YELLOW}[6/6] Creating Tableflow pipeline for orders topic...${NC}"

  CP_BROKER_DNS="kafka.confluent.svc.cluster.local"
  cp "$TABLEFLOW_PIPELINE_TEMPLATE" "$TABLEFLOW_PIPELINE_FILE"
  sed -i '' "s|<CP_BROKER_DNS>|${CP_BROKER_DNS}|g" "$TABLEFLOW_PIPELINE_FILE"
  sed -i '' "s|<BUCKET_URL>|${BUCKET_URL}|g" "$TABLEFLOW_PIPELINE_FILE"
  echo -e "${GREEN}✓ Generated: ${TABLEFLOW_PIPELINE_FILE}${NC}"

  pushd "$TABLEFLOW_PIPELINE_TF_DIR" >/dev/null
  terraform init -input=false >/dev/null

  TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
  TF_VAR_tableflow_virtual_cluster_id="$WARPSTREAM_VIRTUAL_CLUSTER_ID" \
  terraform apply -auto-approve

  popd >/dev/null
  echo -e "${GREEN}✓ Tableflow pipeline created${NC}"
}
