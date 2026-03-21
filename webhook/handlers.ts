/**
 * handlers.ts — Map GitHub webhook events to gstack skill prompts
 *
 * Each handler returns a string prompt to inject into the Claude Code session,
 * or null if the event should be ignored.
 */

export interface GitHubPushEvent {
  ref: string;
  repository: { full_name: string };
  commits: Array<{ id: string; message: string }>;
  pusher: { name: string };
}

export interface GitHubPullRequestEvent {
  action: string;
  pull_request: {
    number: number;
    title: string;
    html_url: string;
    user: { login: string };
    head: { ref: string };
    base: { ref: string };
    draft: boolean;
  };
  repository: { full_name: string };
}

export interface GitHubWorkflowRunEvent {
  action: string;
  workflow_run: {
    name: string;
    conclusion: string | null;
    status: string;
    html_url: string;
    head_branch: string;
    head_sha: string;
  };
  repository: { full_name: string };
}

export interface GitHubIssuesEvent {
  action: string;
  issue: {
    number: number;
    title: string;
    html_url: string;
    body: string | null;
    user: { login: string };
  };
  repository: { full_name: string };
}

export interface GitHubPullRequestReviewEvent {
  action: string;
  review: {
    state: string;
    user: { login: string };
  };
  pull_request: {
    number: number;
    title: string;
    html_url: string;
    head: { ref: string };
  };
  repository: { full_name: string };
}

// ---

export function handlePullRequest(payload: GitHubPullRequestEvent): string | null {
  const { action, pull_request: pr, repository } = payload;

  // New PR opened (not draft) → /review
  if (action === "opened" && !pr.draft) {
    return [
      `New pull request opened on ${repository.full_name}: #${pr.number} "${pr.title}" by ${pr.user.login}.`,
      `Branch: ${pr.head.ref} → ${pr.base.ref}.`,
      `PR URL: ${pr.html_url}`,
      ``,
      `Run /review on this PR. Focus on correctness, security, and whether this is ready to ship.`,
    ].join("\n");
  }

  // Draft converted to ready → /review
  if (action === "ready_for_review") {
    return [
      `PR #${pr.number} "${pr.title}" on ${repository.full_name} is now ready for review.`,
      `PR URL: ${pr.html_url}`,
      ``,
      `Run /review on this PR.`,
    ].join("\n");
  }

  return null;
}

export function handlePullRequestReview(payload: GitHubPullRequestReviewEvent): string | null {
  const { action, review, pull_request: pr, repository } = payload;

  // PR approved → attempt /ship
  if (action === "submitted" && review.state === "approved") {
    return [
      `PR #${pr.number} "${pr.title}" on ${repository.full_name} has been approved by ${review.user.login}.`,
      `Branch: ${pr.head.ref}`,
      `PR URL: ${pr.html_url}`,
      ``,
      `Check if CI is passing. If all checks are green, run /ship to merge and deploy.`,
      `If CI is still running, wait and check back — do not ship until tests pass.`,
    ].join("\n");
  }

  return null;
}

export function handleWorkflowRun(payload: GitHubWorkflowRunEvent): string | null {
  const { action, workflow_run: run, repository } = payload;

  // Build/workflow failed → /investigate
  if (action === "completed" && run.conclusion === "failure") {
    return [
      `CI workflow "${run.name}" failed on ${repository.full_name}.`,
      `Branch: ${run.head_branch} (${run.head_sha.slice(0, 7)})`,
      `Details: ${run.html_url}`,
      ``,
      `Run /investigate to find the root cause. Check recent commits on this branch,`,
      `look at the failure logs, and either fix it or post a summary to Discord with the diagnosis.`,
    ].join("\n");
  }

  return null;
}

export function handleIssues(payload: GitHubIssuesEvent): string | null {
  const { action, issue, repository } = payload;

  // New issue filed → /plan-ceo-review
  if (action === "opened") {
    const body = issue.body ? `\n\nIssue body:\n${issue.body.slice(0, 500)}` : "";
    return [
      `New issue filed on ${repository.full_name}: #${issue.number} "${issue.title}" by ${issue.user.login}.`,
      `Issue URL: ${issue.html_url}${body}`,
      ``,
      `Run /plan-ceo-review on this issue. Assess whether it's worth doing, what the scope is,`,
      `and what a good first approach looks like. Post a brief take to Discord.`,
    ].join("\n");
  }

  return null;
}

export function handlePush(payload: GitHubPushEvent): string | null {
  // Only act on pushes to main/master — others are covered by PR events
  const branch = payload.ref.replace("refs/heads/", "");
  if (branch !== "main" && branch !== "master") return null;

  // More than 3 commits in one push is worth noting
  if (payload.commits.length > 3) {
    const summary = payload.commits
      .slice(0, 5)
      .map((c) => `- ${c.id.slice(0, 7)}: ${c.message.split("\n")[0]}`)
      .join("\n");

    return [
      `${payload.commits.length} commits pushed directly to ${branch} on ${payload.repository.full_name} by ${payload.pusher.name}.`,
      ``,
      `Recent commits:`,
      summary,
      ``,
      `Check if /document-release should be run to capture these changes in the changelog.`,
    ].join("\n");
  }

  return null;
}
