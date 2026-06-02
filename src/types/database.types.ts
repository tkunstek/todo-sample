// PLACEHOLDER — regenerate with `npm run gen:types` against the linked Supabase
// project (plan Task 21). Loose-but-valid shape so the typed client compiles.
export type Database = {
  public: {
    Tables: {
      [table: string]: {
        Row: Record<string, unknown>
        Insert: Record<string, unknown>
        Update: Record<string, unknown>
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
