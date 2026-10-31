import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { Service } from '@deepseek-ai/cordis';
import Schema from '@deepseek-ai/schemastery';

function parseFrontMatter(text) {
  const match = text.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n([\s\S]*)$/);
  if (!match) return { meta: {}, body: text.trim() };
  const meta = {};
  for (const line of match[1].split(/\r?\n/)) {
    const index = line.indexOf(':');
    if (index < 0) continue;
    const key = line.slice(0, index).trim();
    const value = line.slice(index + 1).trim();
    if (key) meta[key] = value.replace(/^['"]|['"]$/g, '');
  }
  return { meta, body: match[2].trim() };
}

function readJsonIfExists(root, file) {
  return readFile(join(root, file), 'utf8').then(JSON.parse).catch(() => undefined);
}

export class RolePresetService extends Service {
  static inject = ['systemPrompt'];
  static Config = Schema.object({
    default: Schema.string().default(''),
    roots: Schema.array(Schema.object({ path: Schema.string(), trust: Schema.string().default('user') })).default([]),
    includeUserRoot: Schema.boolean().default(false),
  });

  constructor(ctx, config = {}) {
    super(ctx, 'agentPresets');
    this.config = config;
    this.entries = new Map();
    this.loaded = false;
  }

  async load() {
    if (this.loaded) return;
    this.loaded = true;
    const configured = (this.config.roots ?? []).map((entry) => resolve(entry.path ?? entry));
    const roots = configured.length > 0 ? configured : [resolve(process.env.DSH_PRESET_ROOT ?? './presets')];
    for (const root of roots) {
      let files = [];
      try { files = await readdir(root); } catch { continue; }
      for (const file of files.filter((name) => /^preset\..+\.md$/i.test(name))) {
        const id = file.slice('preset.'.length, -'.md'.length);
        const parsed = parseFrontMatter(await readFile(join(root, file), 'utf8'));
        const metadata = await readJsonIfExists(root, `preset.${id}.json`) ?? {};
        const fullId = metadata.id ?? `shiny-colors.${id}`;
        this.entries.set(fullId, {
          id: fullId,
          name: metadata.displayName ?? parsed.meta.name ?? id,
          description: metadata.notes ?? parsed.meta.description ?? '',
          aliases: metadata.aliases ?? [],
          prompt: parsed.body,
        });
      }
    }
  }

  async list() {
    await this.load();
    return [...this.entries.values()].map(({ id, name, description }) => ({ id, name, description }));
  }

  async resolve(id = this.config.default) {
    await this.load();
    const wanted = String(id ?? this.config.default);
    const entry = [...this.entries.values()].find((candidate) => candidate.id === wanted || candidate.aliases.includes(wanted));
    if (!entry) throw new Error(`unknown role preset: ${wanted}`);
    return { id: entry.id };
  }

  async mount(agentCtx, id) {
    await this.load();
    const entry = this.entries.get(id);
    if (!entry) throw new Error(`unknown role preset: ${id}`);
    agentCtx.systemPrompt.section({
      name: `shiny-colors:role:${entry.id}`,
      order: 88,
      text: entry.prompt,
    });
  }

  serviceFor(_agent, name) {
    return name === 'compaction' ? undefined : undefined;
  }
}

export default RolePresetService;

