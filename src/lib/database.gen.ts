export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      _bak_gp_credly_sanitize_v1: {
        Row: {
          category: string | null
          created_at: string | null
          id: string
          member_id: string | null
          payload: Json | null
          points: number | null
          reason: string | null
          run_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string | null
          id: string
          member_id?: string | null
          payload?: Json | null
          points?: number | null
          reason?: string | null
          run_at: string
        }
        Update: {
          category?: string | null
          created_at?: string | null
          id?: string
          member_id?: string | null
          payload?: Json | null
          points?: number | null
          reason?: string | null
          run_at?: string
        }
        Relationships: []
      }
      announcements: {
        Row: {
          created_at: string | null
          created_by: string | null
          ends_at: string | null
          id: string
          is_active: boolean | null
          link_text: string | null
          link_url: string | null
          message: string | null
          starts_at: string | null
          title: string
          type: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          ends_at?: string | null
          id?: string
          is_active?: boolean | null
          link_text?: string | null
          link_url?: string | null
          message?: string | null
          starts_at?: string | null
          title: string
          type?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          ends_at?: string | null
          id?: string
          is_active?: boolean | null
          link_text?: string | null
          link_url?: string | null
          message?: string | null
          starts_at?: string | null
          title?: string
          type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      artifacts: {
        Row: {
          created_at: string | null
          cycle: number | null
          description: string | null
          id: string
          member_id: string
          published_at: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string | null
          submitted_at: string | null
          title: string
          tribe_id: number | null
          type: string
          updated_at: string | null
          url: string | null
        }
        Insert: {
          created_at?: string | null
          cycle?: number | null
          description?: string | null
          id?: string
          member_id: string
          published_at?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string | null
          submitted_at?: string | null
          title: string
          tribe_id?: number | null
          type: string
          updated_at?: string | null
          url?: string | null
        }
        Update: {
          created_at?: string | null
          cycle?: number | null
          description?: string | null
          id?: string
          member_id?: string
          published_at?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string | null
          submitted_at?: string | null
          title?: string
          tribe_id?: number | null
          type?: string
          updated_at?: string | null
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "artifacts_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "artifacts_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "artifacts_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "artifacts_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "artifacts_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "artifacts_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "artifacts_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "artifacts_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance: {
        Row: {
          corrected_by: string | null
          created_at: string | null
          event_id: string
          id: string
          member_id: string
          notes: string | null
          present: boolean
          registered_by: string | null
          updated_at: string | null
        }
        Insert: {
          corrected_by?: string | null
          created_at?: string | null
          event_id: string
          id?: string
          member_id: string
          notes?: string | null
          present?: boolean
          registered_by?: string | null
          updated_at?: string | null
        }
        Update: {
          corrected_by?: string | null
          created_at?: string | null
          event_id?: string
          id?: string
          member_id?: string
          notes?: string | null
          present?: boolean
          registered_by?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      certificates: {
        Row: {
          cycle: number | null
          description: string | null
          id: string
          issued_at: string | null
          issued_by: string | null
          member_id: string
          pdf_url: string | null
          title: string
          type: string
          verification_code: string | null
        }
        Insert: {
          cycle?: number | null
          description?: string | null
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          member_id: string
          pdf_url?: string | null
          title: string
          type: string
          verification_code?: string | null
        }
        Update: {
          cycle?: number | null
          description?: string | null
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          member_id?: string
          pdf_url?: string | null
          title?: string
          type?: string
          verification_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      change_requests: {
        Row: {
          cr_number: string
          created_at: string | null
          description: string | null
          id: string
          priority: string | null
          requested_by: string | null
          status: string | null
          title: string
          updated_at: string | null
        }
        Insert: {
          cr_number: string
          created_at?: string | null
          description?: string | null
          id?: string
          priority?: string | null
          requested_by?: string | null
          status?: string | null
          title: string
          updated_at?: string | null
        }
        Update: {
          cr_number?: string
          created_at?: string | null
          description?: string | null
          id?: string
          priority?: string | null
          requested_by?: string | null
          status?: string | null
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      comms_metrics_daily: {
        Row: {
          audience: number | null
          channel: string
          created_at: string
          created_by: string | null
          engagement_rate: number | null
          id: number
          leads: number | null
          metric_date: string
          payload: Json
          publish_batch_id: string | null
          published_at: string | null
          published_by: string | null
          reach: number | null
          source: string
          updated_at: string
        }
        Insert: {
          audience?: number | null
          channel: string
          created_at?: string
          created_by?: string | null
          engagement_rate?: number | null
          id?: number
          leads?: number | null
          metric_date: string
          payload?: Json
          publish_batch_id?: string | null
          published_at?: string | null
          published_by?: string | null
          reach?: number | null
          source?: string
          updated_at?: string
        }
        Update: {
          audience?: number | null
          channel?: string
          created_at?: string
          created_by?: string | null
          engagement_rate?: number | null
          id?: number
          leads?: number | null
          metric_date?: string
          payload?: Json
          publish_batch_id?: string | null
          published_at?: string | null
          published_by?: string | null
          reach?: number | null
          source?: string
          updated_at?: string
        }
        Relationships: []
      }
      comms_metrics_ingestion_log: {
        Row: {
          context: Json
          created_at: string
          error_message: string | null
          fetched_rows: number
          finished_at: string | null
          id: number
          invalid_rows: number
          run_key: string
          source: string
          status: string
          triggered_by: string
          upserted_rows: number
        }
        Insert: {
          context?: Json
          created_at?: string
          error_message?: string | null
          fetched_rows?: number
          finished_at?: string | null
          id?: number
          invalid_rows?: number
          run_key: string
          source: string
          status: string
          triggered_by?: string
          upserted_rows?: number
        }
        Update: {
          context?: Json
          created_at?: string
          error_message?: string | null
          fetched_rows?: number
          finished_at?: string | null
          id?: number
          invalid_rows?: number
          run_key?: string
          source?: string
          status?: string
          triggered_by?: string
          upserted_rows?: number
        }
        Relationships: []
      }
      comms_metrics_publish_log: {
        Row: {
          batch_id: string
          context: Json
          created_at: string
          id: number
          published_by: string | null
          published_rows: number
          source: string
          target_date: string
        }
        Insert: {
          batch_id: string
          context?: Json
          created_at?: string
          id?: number
          published_by?: string | null
          published_rows?: number
          source: string
          target_date: string
        }
        Update: {
          batch_id?: string
          context?: Json
          created_at?: string
          id?: number
          published_by?: string | null
          published_rows?: number
          source?: string
          target_date?: string
        }
        Relationships: []
      }
      course_progress: {
        Row: {
          completed_at: string | null
          course_id: number | null
          id: string
          member_id: string | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          completed_at?: string | null
          course_id?: number | null
          id?: string
          member_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          completed_at?: string | null
          course_id?: number | null
          id?: string
          member_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "course_progress_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      courses: {
        Row: {
          category: string | null
          code: string
          id: number
          is_free: boolean | null
          name: string
          sort_order: number | null
          url: string | null
        }
        Insert: {
          category?: string | null
          code: string
          id?: number
          is_free?: boolean | null
          name: string
          sort_order?: number | null
          url?: string | null
        }
        Update: {
          category?: string | null
          code?: string
          id?: number
          is_free?: boolean | null
          name?: string
          sort_order?: number | null
          url?: string | null
        }
        Relationships: []
      }
      events: {
        Row: {
          audience_level: string | null
          created_at: string | null
          created_by: string | null
          date: string
          duration_actual: number | null
          duration_minutes: number
          id: string
          is_recorded: boolean | null
          meeting_link: string | null
          recurrence_group: string | null
          title: string
          tribe_id: number | null
          type: string
          updated_at: string | null
          youtube_url: string | null
        }
        Insert: {
          audience_level?: string | null
          created_at?: string | null
          created_by?: string | null
          date: string
          duration_actual?: number | null
          duration_minutes?: number
          id?: string
          is_recorded?: boolean | null
          meeting_link?: string | null
          recurrence_group?: string | null
          title: string
          tribe_id?: number | null
          type: string
          updated_at?: string | null
          youtube_url?: string | null
        }
        Update: {
          audience_level?: string | null
          created_at?: string | null
          created_by?: string | null
          date?: string
          duration_actual?: number | null
          duration_minutes?: number
          id?: string
          is_recorded?: boolean | null
          meeting_link?: string | null
          recurrence_group?: string | null
          title?: string
          tribe_id?: number | null
          type?: string
          updated_at?: string | null
          youtube_url?: string | null
        }
        Relationships: []
      }
      gamification_points: {
        Row: {
          category: string
          created_at: string | null
          id: string
          member_id: string
          points: number
          reason: string
          ref_id: string | null
        }
        Insert: {
          category: string
          created_at?: string | null
          id?: string
          member_id: string
          points: number
          reason: string
          ref_id?: string | null
        }
        Update: {
          category?: string
          created_at?: string | null
          id?: string
          member_id?: string
          points?: number
          reason?: string
          ref_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      global_links: {
        Row: {
          category: string | null
          key: string
          label: string
          updated_at: string | null
          url: string
        }
        Insert: {
          category?: string | null
          key: string
          label: string
          updated_at?: string | null
          url: string
        }
        Update: {
          category?: string | null
          key?: string
          label?: string
          updated_at?: string | null
          url?: string
        }
        Relationships: []
      }
      home_schedule: {
        Row: {
          id: number
          kickoff_at: string
          platform_label: string
          recurring_end_brt: string
          recurring_start_brt: string
          recurring_weekday: number
          selection_deadline_at: string
          updated_at: string
        }
        Insert: {
          id?: number
          kickoff_at: string
          platform_label?: string
          recurring_end_brt: string
          recurring_start_brt: string
          recurring_weekday: number
          selection_deadline_at: string
          updated_at?: string
        }
        Update: {
          id?: number
          kickoff_at?: string
          platform_label?: string
          recurring_end_brt?: string
          recurring_start_brt?: string
          recurring_weekday?: number
          selection_deadline_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      knowledge_assets: {
        Row: {
          created_at: string
          created_by: string | null
          external_id: string
          id: string
          is_active: boolean
          language: string
          metadata: Json
          published_at: string | null
          source: string
          source_url: string | null
          summary: string | null
          tags: string[]
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          external_id: string
          id?: string
          is_active?: boolean
          language?: string
          metadata?: Json
          published_at?: string | null
          source: string
          source_url?: string | null
          summary?: string | null
          tags?: string[]
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          external_id?: string
          id?: string
          is_active?: boolean
          language?: string
          metadata?: Json
          published_at?: string | null
          source?: string
          source_url?: string | null
          summary?: string | null
          tags?: string[]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_chunks: {
        Row: {
          asset_id: string
          chunk_index: number
          content: string
          created_at: string
          embedding: string | null
          id: string
          metadata: Json
          token_estimate: number | null
        }
        Insert: {
          asset_id: string
          chunk_index: number
          content: string
          created_at?: string
          embedding?: string | null
          id?: string
          metadata?: Json
          token_estimate?: number | null
        }
        Update: {
          asset_id?: string
          chunk_index?: number
          content?: string
          created_at?: string
          embedding?: string | null
          id?: string
          metadata?: Json
          token_estimate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_chunks_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "knowledge_assets"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_ingestion_runs: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          metadata: Json
          rows_chunked: number
          rows_received: number
          rows_upserted: number
          run_key: string
          source: string
          status: string
          triggered_by: string | null
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key: string
          source: string
          status: string
          triggered_by?: string | null
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key?: string
          source?: string
          status?: string
          triggered_by?: string | null
        }
        Relationships: []
      }
      knowledge_insights: {
        Row: {
          asset_id: string | null
          chunk_id: string | null
          confidence_score: number | null
          created_at: string
          detected_at: string
          evidence_quote: string | null
          evidence_url: string | null
          id: string
          impact_score: number
          insight_type: string
          metadata: Json
          reviewed_at: string | null
          reviewed_by: string | null
          sentiment_score: number | null
          source: string
          status: string
          summary: string
          taxonomy_area: string
          title: string
          updated_at: string
          urgency_score: number
        }
        Insert: {
          asset_id?: string | null
          chunk_id?: string | null
          confidence_score?: number | null
          created_at?: string
          detected_at?: string
          evidence_quote?: string | null
          evidence_url?: string | null
          id?: string
          impact_score?: number
          insight_type: string
          metadata?: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          sentiment_score?: number | null
          source: string
          status?: string
          summary: string
          taxonomy_area: string
          title: string
          updated_at?: string
          urgency_score?: number
        }
        Update: {
          asset_id?: string | null
          chunk_id?: string | null
          confidence_score?: number | null
          created_at?: string
          detected_at?: string
          evidence_quote?: string | null
          evidence_url?: string | null
          id?: string
          impact_score?: number
          insight_type?: string
          metadata?: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          sentiment_score?: number | null
          source?: string
          status?: string
          summary?: string
          taxonomy_area?: string
          title?: string
          updated_at?: string
          urgency_score?: number
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_insights_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "knowledge_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_chunk_id_fkey"
            columns: ["chunk_id"]
            isOneToOne: false
            referencedRelation: "knowledge_chunks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_insights_ingestion_log: {
        Row: {
          created_at: string
          error_message: string | null
          finished_at: string | null
          id: number
          metadata: Json
          rows_chunked: number
          rows_received: number
          rows_upserted: number
          run_key: string
          status: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          finished_at?: string | null
          id?: number
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key: string
          status: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          finished_at?: string | null
          id?: number
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key?: string
          status?: string
        }
        Relationships: []
      }
      member_chapter_affiliations: {
        Row: {
          affiliated_since: string | null
          affiliation_type: string
          catalyst_project: boolean | null
          chapter_code: string
          consent_date: string | null
          consent_given: boolean | null
          consent_purpose: string | null
          created_at: string | null
          id: string
          is_current: boolean | null
          member_id: string | null
          notes: string | null
          updated_at: string | null
        }
        Insert: {
          affiliated_since?: string | null
          affiliation_type?: string
          catalyst_project?: boolean | null
          chapter_code: string
          consent_date?: string | null
          consent_given?: boolean | null
          consent_purpose?: string | null
          created_at?: string | null
          id?: string
          is_current?: boolean | null
          member_id?: string | null
          notes?: string | null
          updated_at?: string | null
        }
        Update: {
          affiliated_since?: string | null
          affiliation_type?: string
          catalyst_project?: boolean | null
          chapter_code?: string
          consent_date?: string | null
          consent_given?: boolean | null
          consent_purpose?: string | null
          created_at?: string | null
          id?: string
          is_current?: boolean | null
          member_id?: string | null
          notes?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_chapter_affiliations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_chapter_affiliations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_chapter_affiliations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_chapter_affiliations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      member_cycle_history: {
        Row: {
          chapter: string | null
          created_at: string | null
          cycle_code: string
          cycle_end: string | null
          cycle_label: string
          cycle_start: string | null
          designations: string[] | null
          id: string
          is_active: boolean | null
          member_id: string | null
          member_name_snapshot: string
          notes: string | null
          operational_role: string
          tribe_id: number | null
          tribe_name: string | null
        }
        Insert: {
          chapter?: string | null
          created_at?: string | null
          cycle_code: string
          cycle_end?: string | null
          cycle_label: string
          cycle_start?: string | null
          designations?: string[] | null
          id?: string
          is_active?: boolean | null
          member_id?: string | null
          member_name_snapshot: string
          notes?: string | null
          operational_role?: string
          tribe_id?: number | null
          tribe_name?: string | null
        }
        Update: {
          chapter?: string | null
          created_at?: string | null
          cycle_code?: string
          cycle_end?: string | null
          cycle_label?: string
          cycle_start?: string | null
          designations?: string[] | null
          id?: string
          is_active?: boolean | null
          member_id?: string | null
          member_name_snapshot?: string
          notes?: string | null
          operational_role?: string
          tribe_id?: number | null
          tribe_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      members: {
        Row: {
          auth_id: string | null
          chapter: string
          country: string | null
          cpmai_certified: boolean | null
          cpmai_certified_at: string | null
          created_at: string | null
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          current_cycle_active: boolean | null
          cycles: string[] | null
          designations: string[] | null
          email: string
          id: string
          inactivated_at: string | null
          inactivation_reason: string | null
          is_active: boolean | null
          is_superadmin: boolean | null
          linkedin_url: string | null
          name: string
          operational_role: string | null
          phone: string | null
          phone_encrypted: string | null
          photo_url: string | null
          pmi_id: string | null
          pmi_id_encrypted: string | null
          pmi_id_verified: boolean | null
          secondary_emails: string[] | null
          state: string | null
          tribe_id: number | null
          updated_at: string | null
        }
        Insert: {
          auth_id?: string | null
          chapter?: string
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          email: string
          id?: string
          inactivated_at?: string | null
          inactivation_reason?: string | null
          is_active?: boolean | null
          is_superadmin?: boolean | null
          linkedin_url?: string | null
          name: string
          operational_role?: string | null
          phone?: string | null
          phone_encrypted?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          pmi_id_encrypted?: string | null
          pmi_id_verified?: boolean | null
          secondary_emails?: string[] | null
          state?: string | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Update: {
          auth_id?: string | null
          chapter?: string
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          email?: string
          id?: string
          inactivated_at?: string | null
          inactivation_reason?: string | null
          is_active?: boolean | null
          is_superadmin?: boolean | null
          linkedin_url?: string | null
          name?: string
          operational_role?: string | null
          phone?: string | null
          phone_encrypted?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          pmi_id_encrypted?: string | null
          pmi_id_verified?: boolean | null
          secondary_emails?: string[] | null
          state?: string | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Relationships: []
      }
      presentations: {
        Row: {
          created_at: string | null
          created_by: string | null
          cycle: string
          date: string
          description: string | null
          id: string
          snapshot_url: string | null
          title: string
          url: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          cycle: string
          date: string
          description?: string | null
          id?: string
          snapshot_url?: string | null
          title: string
          url?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          cycle?: string
          date?: string
          description?: string | null
          id?: string
          snapshot_url?: string | null
          title?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "presentations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "presentations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "presentations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "presentations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_meeting_slots: {
        Row: {
          created_at: string | null
          day_of_week: number
          id: string
          is_active: boolean | null
          time_end: string
          time_start: string
          tribe_id: number
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          day_of_week: number
          id?: string
          is_active?: boolean | null
          time_end: string
          time_start: string
          tribe_id: number
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          day_of_week?: number
          id?: string
          is_active?: boolean | null
          time_end?: string
          time_start?: string
          tribe_id?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_meeting_slots_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_selections: {
        Row: {
          id: string
          member_id: string | null
          selected_at: string | null
          tribe_id: number
        }
        Insert: {
          id?: string
          member_id?: string | null
          selected_at?: string | null
          tribe_id: number
        }
        Update: {
          id?: string
          member_id?: string | null
          selected_at?: string | null
          tribe_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribes: {
        Row: {
          drive_url: string | null
          id: number
          leader_member_id: string | null
          meeting_day: string | null
          meeting_link: string | null
          meeting_schedule: string | null
          meeting_time_end: string | null
          meeting_time_start: string | null
          miro_url: string | null
          name: string
          notes: string | null
          quadrant: number
          quadrant_name: string
          updated_at: string | null
          updated_by: string | null
          whatsapp_url: string | null
        }
        Insert: {
          drive_url?: string | null
          id: number
          leader_member_id?: string | null
          meeting_day?: string | null
          meeting_link?: string | null
          meeting_schedule?: string | null
          meeting_time_end?: string | null
          meeting_time_start?: string | null
          miro_url?: string | null
          name: string
          notes?: string | null
          quadrant: number
          quadrant_name: string
          updated_at?: string | null
          updated_by?: string | null
          whatsapp_url?: string | null
        }
        Update: {
          drive_url?: string | null
          id?: number
          leader_member_id?: string | null
          meeting_day?: string | null
          meeting_link?: string | null
          meeting_schedule?: string | null
          meeting_time_end?: string | null
          meeting_time_start?: string | null
          miro_url?: string | null
          name?: string
          notes?: string | null
          quadrant?: number
          quadrant_name?: string
          updated_at?: string | null
          updated_by?: string | null
          whatsapp_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      gamification_leaderboard: {
        Row: {
          artifact_points: number | null
          attendance_points: number | null
          bonus_points: number | null
          chapter: string | null
          course_points: number | null
          designations: string[] | null
          member_id: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          role: string | null
          total_points: number | null
        }
        Relationships: []
      }
      impact_hours_summary: {
        Row: {
          impact_hours: number | null
          impact_hours_raw: number | null
          total_attendances: number | null
          total_events: number | null
          tribe_id: number | null
        }
        Relationships: []
      }
      impact_hours_total: {
        Row: {
          annual_target_hours: number | null
          percent_of_target: number | null
          total_attendances: number | null
          total_events: number | null
          total_impact_hours: number | null
        }
        Relationships: []
      }
      member_attendance_summary: {
        Row: {
          chapter: string | null
          designations: string[] | null
          events_attended: number | null
          member_id: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          role: string | null
          total_hours: number | null
        }
        Relationships: []
      }
      public_members: {
        Row: {
          chapter: string | null
          current_cycle_active: boolean | null
          designations: string[] | null
          id: string | null
          linkedin_url: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          role: string | null
          tribe_id: number | null
        }
        Insert: {
          chapter?: string | null
          current_cycle_active?: boolean | null
          designations?: string[] | null
          id?: string | null
          linkedin_url?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          role?: never
          tribe_id?: number | null
        }
        Update: {
          chapter?: string | null
          current_cycle_active?: boolean | null
          designations?: string[] | null
          id?: string | null
          linkedin_url?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          role?: never
          tribe_id?: number | null
        }
        Relationships: []
      }
      recurring_event_groups: {
        Row: {
          first_date: string | null
          last_date: string | null
          meeting_link: string | null
          past_events: number | null
          recurrence_group: string | null
          total_events: number | null
          tribe_id: number | null
          type: string | null
          upcoming_events: number | null
        }
        Relationships: []
      }
      vw_exec_cert_timeline: {
        Row: {
          avg_days_to_tier1: number | null
          avg_days_to_tier2: number | null
          cohort_month: string | null
          members_in_cohort: number | null
          members_with_tier1: number | null
          members_with_tier2: number | null
          pct_with_tier1: number | null
          pct_with_tier2: number | null
        }
        Relationships: []
      }
      vw_exec_funnel: {
        Row: {
          active_members: number | null
          members_with_credly_url: number | null
          members_with_full_core_trail: number | null
          members_with_published_artifact: number | null
          members_with_tier1: number | null
          members_with_tier2_plus: number | null
          snapshot_date: string | null
          total_members: number | null
          total_published_artifacts: number | null
        }
        Relationships: []
      }
      vw_exec_skills_radar: {
        Row: {
          avg_points: number | null
          badges_count: number | null
          members_with_signal: number | null
          radar_axis: string | null
          total_points: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      admin_force_tribe_selection: {
        Args: { p_member_id: string; p_tribe_id: number }
        Returns: Json
      }
      admin_get_tribe_allocations: { Args: never; Returns: Json }
      admin_inactivate_member: {
        Args: { p_member_id: string; p_reason?: string }
        Returns: Json
      }
      admin_list_members: {
        Args: {
          p_active?: boolean
          p_chapter?: string
          p_limit?: number
          p_offset?: number
          p_role?: string
          p_search?: string
        }
        Returns: Json
      }
      admin_reactivate_member: { Args: { p_member_id: string }; Returns: Json }
      admin_remove_tribe_selection: {
        Args: { p_member_id: string }
        Returns: Json
      }
      admin_update_member: {
        Args: {
          p_chapter?: string
          p_current_cycle_active?: boolean
          p_member_id: string
          p_role?: string
          p_roles?: string[]
        }
        Returns: Json
      }
      can_manage_comms_metrics: { Args: never; Returns: boolean }
      can_manage_knowledge: { Args: never; Returns: boolean }
      comms_metrics_latest: {
        Args: never
        Returns: {
          audience: number
          engagement: number
          leads: number
          metric_date: string
          reach: number
          rows_count: number
          updated_at: string
        }[]
      }
      comms_metrics_latest_by_channel: {
        Args: { p_days?: number }
        Returns: {
          audience: number
          channel: string
          engagement: number
          leads: number
          metric_date: string
          reach: number
          source: string
          updated_at: string
        }[]
      }
      compute_legacy_role: {
        Args: { p_desigs: string[]; p_op_role: string }
        Returns: string
      }
      compute_legacy_roles: {
        Args: { p_desigs: string[]; p_op_role: string }
        Returns: string[]
      }
      create_event:
        | {
            Args: {
              p_date: string
              p_duration_minutes: number
              p_title: string
              p_tribe_id?: number
              p_type: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_audience_level?: string
              p_date: string
              p_duration_minutes: number
              p_title: string
              p_tribe_id?: number
              p_type: string
            }
            Returns: Json
          }
      create_recurring_weekly_events: {
        Args: {
          p_duration_minutes: number
          p_is_recorded?: boolean
          p_meeting_link?: string
          p_n_weeks: number
          p_start_date: string
          p_title_template: string
          p_tribe_id?: number
          p_type: string
        }
        Returns: Json
      }
      current_member_tier_rank: { Args: never; Returns: number }
      decrypt_sensitive: { Args: { val: string }; Returns: string }
      deselect_tribe: { Args: never; Returns: Json }
      encrypt_sensitive: { Args: { val: string }; Returns: string }
      exec_cert_timeline: {
        Args: { p_months?: number }
        Returns: {
          avg_days_to_tier1: number
          avg_days_to_tier2: number
          cohort_month: string
          members_in_cohort: number
          members_with_tier1: number
          members_with_tier2: number
          pct_with_tier1: number
          pct_with_tier2: number
        }[]
      }
      exec_funnel_summary: {
        Args: never
        Returns: {
          active_members: number
          members_with_credly_url: number
          members_with_full_core_trail: number
          members_with_published_artifact: number
          members_with_tier1: number
          members_with_tier2_plus: number
          snapshot_date: string
          total_members: number
          total_published_artifacts: number
        }[]
      }
      exec_skills_radar: {
        Args: never
        Returns: {
          avg_points: number
          badges_count: number
          members_with_signal: number
          radar_axis: string
          total_points: number
        }[]
      }
      get_events_with_attendance: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_member_by_auth: { Args: never; Returns: Json }
      get_tribe_counts: {
        Args: never
        Returns: {
          member_count: number
          tribe_id: number
        }[]
      }
      get_tribe_event_roster: { Args: { p_event_id: string }; Returns: Json }
      has_min_tier: { Args: { required_rank: number }; Returns: boolean }
      knowledge_assets_latest: {
        Args: { p_limit?: number; p_source?: string }
        Returns: {
          asset_id: string
          chunk_count: number
          external_id: string
          language: string
          published_at: string
          source: string
          source_url: string
          summary: string
          tags: string[]
          title: string
        }[]
      }
      knowledge_insights_backlog_candidates: {
        Args: { p_limit?: number; p_status?: string }
        Returns: {
          confidence_score: number
          detected_at: string
          evidence_url: string
          impact_score: number
          insight_id: string
          insight_type: string
          priority_score: number
          status: string
          taxonomy_area: string
          title: string
          urgency_score: number
        }[]
      }
      knowledge_insights_overview: {
        Args: { p_days?: number; p_status?: string }
        Returns: {
          avg_impact: number
          avg_urgency: number
          insight_type: string
          items: number
          max_detected_at: string
          taxonomy_area: string
        }[]
      }
      knowledge_search: {
        Args: {
          p_match_count?: number
          p_query_embedding: string
          p_source?: string
        }
        Returns: {
          asset_id: string
          chunk_id: string
          similarity: number
          snippet: string
          source: string
          source_url: string
          tags: string[]
          title: string
        }[]
      }
      knowledge_search_text: {
        Args: { p_match_count?: number; p_query: string; p_source?: string }
        Returns: {
          asset_id: string
          chunk_id: string
          rank: number
          snippet: string
          source: string
          source_url: string
          tags: string[]
          title: string
        }[]
      }
      mark_member_present: {
        Args: { p_event_id: string; p_member_id: string; p_present?: boolean }
        Returns: Json
      }
      member_self_update:
        | {
            Args: {
              p_linkedin_url?: string
              p_phone?: string
              p_pmi_id?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_credly_url?: string
              p_linkedin_url?: string
              p_phone?: string
              p_pmi_id?: string
            }
            Returns: Json
          }
      publish_comms_metrics_batch: {
        Args: { p_metric_date?: string; p_source?: string }
        Returns: {
          batch_id: string
          published_at: string
          published_rows: number
          source: string
          target_date: string
        }[]
      }
      register_own_presence: { Args: { p_event_id: string }; Returns: Json }
      select_tribe: { Args: { p_tribe_id: number }; Returns: Json }
      set_progress: {
        Args: { p_code: string; p_email: string; p_status: string }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      sync_attendance_points: { Args: never; Returns: Json }
      title_case: { Args: { input: string }; Returns: string }
      update_event:
        | {
            Args: {
              p_date?: string
              p_duration_minutes?: number
              p_event_id: string
              p_is_recorded?: boolean
              p_meeting_link?: string
              p_title?: string
              p_youtube_url?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_audience_level?: string
              p_date?: string
              p_duration_minutes?: number
              p_event_id: string
              p_is_recorded?: boolean
              p_meeting_link?: string
              p_title?: string
              p_youtube_url?: string
            }
            Returns: Json
          }
      update_event_duration: {
        Args: { p_duration_minutes: number; p_event_id: string }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
