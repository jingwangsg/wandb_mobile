export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export class WandbGateway {
  constructor(baseUrl, fetcher = fetch) {
    const url = new URL(baseUrl);
    if (url.protocol !== 'https:') throw new Error('WANDB_BASE_URL must use HTTPS');
    this.url = new URL('/graphql', url);
    this.fetch = fetcher;
  }

  async query(authorization, query, variables = {}) {
    const response = await this.fetch(this.url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20_000),
      headers: {authorization, 'content-type': 'application/json'},
      body: JSON.stringify({query, variables}),
    });
    if (response.status === 401 || response.status === 403) throw new HttpError(response.status, 'W&B authentication or permission denied');
    if (!response.ok) throw new HttpError(502, 'W&B is temporarily unavailable');
    const result = await response.json();
    if (result.errors?.length) throw new HttpError(400, result.errors[0].message);
    return result.data;
  }

  async viewer(authorization) {
    const data = await this.query(authorization, 'query RelayViewer { viewer { id } }');
    if (!data?.viewer?.id) throw new HttpError(401, 'Sign in with a valid W&B API key');
    return data.viewer.id;
  }

  async project(authorization, entity, project) {
    const data = await this.query(authorization, `query RelayProject($entity: String!, $project: String!) {
      project(entityName: $entity, name: $project) { id readOnly entity { isTeam } }
    }`, {entity, project});
    if (!data?.project || data.project.readOnly) throw new HttpError(403, 'This project is not writable by your account');
    if (!data.project.entity.isTeam) throw new HttpError(400, 'Notifications require a team project');
    return data.project.id;
  }

  async createIntegration(authorization, entity, name, urlEndpoint) {
    const data = await this.query(authorization, `mutation RelayCreateIntegration($input: CreateGenericWebhookIntegrationInput!) {
      createGenericWebhookIntegration(input: $input) { integration { id } }
    }`, {input: {entityName: entity, name, urlEndpoint}});
    return data.createGenericWebhookIntegration.integration.id;
  }

  async createTrigger(authorization, rule, projectId, integrationId) {
    const payload = {
      entity: '${entity_name}', project: '${project_name}', run: '${run_name}',
      ...(rule.metric ? {description: '${metric_current_status}', values: '${metric_values}'} : {state: '${run_status}'}),
    };
    const data = await this.query(authorization, `mutation RelayCreateTrigger($input: CreateFilterTriggerInput!) {
      createFilterTrigger(input: $input) { trigger { id } }
    }`, {input: {
      name: rule.name, enabled: true, scopeID: projectId, scopeType: 'PROJECT',
      triggeringEventType: rule.metric ? 'RUN_METRIC_CHANGE' : 'RUN_STATE',
      eventFilter: JSON.stringify(automationFilter(rule)),
      triggeredActionType: 'GENERIC_WEBHOOK',
      triggeredActionConfig: {genericWebhookActionInput: {integrationID: integrationId, requestPayload: JSON.stringify(payload)}},
    }});
    return data.createFilterTrigger.trigger.id;
  }

  async deleteTrigger(authorization, triggerID) {
    const data = await this.query(authorization, `mutation RelayDeleteTrigger($input: DeleteTriggerInput!) {
      deleteTrigger(input: $input) { success }
    }`, {input: {triggerID}});
    if (data.deleteTrigger.success !== true) throw new HttpError(502, 'W&B did not confirm alert deletion');
  }

  async deleteIntegration(authorization, id) {
    const data = await this.query(authorization, `mutation RelayDeleteIntegration($input: DeleteIntegrationInput!) {
      deleteIntegration(input: $input) { success }
    }`, {input: {id}});
    if (data.deleteIntegration.success !== true) throw new HttpError(502, 'W&B did not confirm webhook deletion');
  }
}

// Wire format follows wandb.automations.events and _run_metric_filters.
export function automationFilter(rule) {
  return {
    run_filter: JSON.stringify({$and: []}),
    ...(rule.metric ? {run_metric_filter: {change_filter: {
      name: rule.metric, agg_op: 'AVERAGE', current_window_size: 10, prior_window_size: 50,
      change_type: rule.basis, change_dir: rule.direction, change_amount: rule.amount,
    }}} : {run_state_filter: {states: ['FAILED']}}),
  };
}
