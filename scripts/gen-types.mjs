// scripts/gen-types.mjs
// Windows-safe types generation using spawnSync with UTF-8 encoding
import { spawnSync } from 'child_process'
import { writeFileSync } from 'fs'

const result = spawnSync(
  'npx',
  ['supabase', 'gen', 'types', 'typescript', '--local'],
  {
    encoding: 'utf8',
    shell: true,
  },
)

if (result.status !== 0) {
  console.error(result.stderr)
  process.exit(result.status)
}

writeFileSync('src/types/database.ts', result.stdout, 'utf8')
console.log('Generated src/types/database.ts')
