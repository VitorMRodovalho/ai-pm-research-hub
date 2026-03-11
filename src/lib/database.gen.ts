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
      admin_links: {
        Row: {
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          icon: string | null
          id: number
          is_active: boolean
          sort_order: number | null
          title: string
          updated_at: string
          url: string
        }
        Insert: {
          category: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon?: string | null
          id?: number
          is_active?: boolean
          sort_order?: number | null
          title: string
          updated_at?: string
          url: string
        }
        Update: {
          category?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon?: string | null
          id?: number
          is_active?: boolean
          sort_order?: number | null
          title?: string
          updated_at?: string
          url?: string
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
          tribe_id: number | null
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
          tribe_id?: number | null
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
          tribe_id?: number | null
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
          {
            foreignKeyName: "announcements_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      artifacts: {
        Row: {
          created_at: string | null
          curation_status: string
          cycle: number | null
          description: string | null
          id: string
          member_id: string
          published_at: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          source: string | null
          status: string | null
          submitted_at: string | null
          tags: string[] | null
          title: string
          trello_card_id: string | null
          tribe_id: number | null
          type: string
          updated_at: string | null
          url: string | null
        }
        Insert: {
          created_at?: string | null
          curation_status?: string
          cycle?: number | null
          description?: string | null
          id?: string
          member_id: string
          published_at?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source?: string | null
          status?: string | null
          submitted_at?: string | null
          tags?: string[] | null
          title: string
          trello_card_id?: string | null
          tribe_id?: number | null
          type: string
          updated_at?: string | null
          url?: string | null
        }
        Update: {
          created_at?: string | null
          curation_status?: string
          cycle?: number | null
          description?: string | null
          id?: string
          member_id?: string
          published_at?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source?: string | null
          status?: string | null
          submitted_at?: string | null
          tags?: string[] | null
          title?: string
          trello_card_id?: string | null
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
      board_items: {
        Row: {
          assignee_id: string | null
          attachments: Json | null
          board_id: string
          checklist: Json | null
          created_at: string
          curation_status: string
          cycle: number | null
          description: string | null
          due_date: string | null
          id: string
          labels: Json | null
          position: number
          reviewer_id: string | null
          source_board: string | null
          source_card_id: string | null
          status: string
          tags: string[] | null
          title: string
          updated_at: string
        }
        Insert: {
          assignee_id?: string | null
          attachments?: Json | null
          board_id: string
          checklist?: Json | null
          created_at?: string
          curation_status?: string
          cycle?: number | null
          description?: string | null
          due_date?: string | null
          id?: string
          labels?: Json | null
          position?: number
          reviewer_id?: string | null
          source_board?: string | null
          source_card_id?: string | null
          status?: string
          tags?: string[] | null
          title: string
          updated_at?: string
        }
        Update: {
          assignee_id?: string | null
          attachments?: Json | null
          board_id?: string
          checklist?: Json | null
          created_at?: string
          curation_status?: string
          cycle?: number | null
          description?: string | null
          due_date?: string | null
          id?: string
          labels?: Json | null
          position?: number
          reviewer_id?: string | null
          source_board?: string | null
          source_card_id?: string | null
          status?: string
          tags?: string[] | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_lifecycle_events: {
        Row: {
          action: string
          actor_member_id: string | null
          board_id: string | null
          created_at: string
          id: number
          item_id: string | null
          new_status: string | null
          previous_status: string | null
          reason: string | null
        }
        Insert: {
          action: string
          actor_member_id?: string | null
          board_id?: string | null
          created_at?: string
          id?: number
          item_id?: string | null
          new_status?: string | null
          previous_status?: string | null
          reason?: string | null
        }
        Update: {
          action?: string
          actor_member_id?: string | null
          board_id?: string | null
          created_at?: string
          id?: number
          item_id?: string | null
          new_status?: string | null
          previous_status?: string | null
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
        ]
      }
      board_source_tribe_map: {
        Row: {
          is_active: boolean
          notes: string | null
          source_board: string
          tribe_id: number
          updated_at: string
        }
        Insert: {
          is_active?: boolean
          notes?: string | null
          source_board: string
          tribe_id: number
          updated_at?: string
        }
        Update: {
          is_active?: boolean
          notes?: string | null
          source_board?: string
          tribe_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_source_tribe_map_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      board_taxonomy_alerts: {
        Row: {
          alert_code: string
          board_id: string | null
          created_at: string
          id: number
          payload: Json
          resolved_at: string | null
          severity: string
        }
        Insert: {
          alert_code: string
          board_id?: string | null
          created_at?: string
          id?: never
          payload?: Json
          resolved_at?: string | null
          severity?: string
        }
        Update: {
          alert_code?: string
          board_id?: string | null
          created_at?: string
          id?: never
          payload?: Json
          resolved_at?: string | null
          severity?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_taxonomy_alerts_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
        ]
      }
      broadcast_log: {
        Row: {
          body: string
          error_detail: string | null
          id: string
          recipient_count: number
          sender_id: string
          sent_at: string
          status: string
          subject: string
          tribe_id: number
        }
        Insert: {
          body: string
          error_detail?: string | null
          id?: string
          recipient_count?: number
          sender_id: string
          sent_at?: string
          status?: string
          subject: string
          tribe_id: number
        }
        Update: {
          body?: string
          error_detail?: string | null
          id?: string
          recipient_count?: number
          sender_id?: string
          sent_at?: string
          status?: string
          subject?: string
          tribe_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
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
      communication_templates: {
        Row: {
          body_html_tpl: string
          created_at: string
          id: number
          is_active: boolean
          label: string
          signature_tpl: string
          slug: string
          subject_tpl: string
          updated_at: string
          variables: string[]
        }
        Insert: {
          body_html_tpl?: string
          created_at?: string
          id?: number
          is_active?: boolean
          label: string
          signature_tpl?: string
          slug: string
          subject_tpl?: string
          updated_at?: string
          variables?: string[]
        }
        Update: {
          body_html_tpl?: string
          created_at?: string
          id?: number
          is_active?: boolean
          label?: string
          signature_tpl?: string
          slug?: string
          subject_tpl?: string
          updated_at?: string
          variables?: string[]
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
      cycles: {
        Row: {
          created_at: string
          cycle_abbr: string
          cycle_code: string
          cycle_color: string
          cycle_end: string | null
          cycle_label: string
          cycle_start: string
          is_current: boolean
          sort_order: number
        }
        Insert: {
          created_at?: string
          cycle_abbr: string
          cycle_code: string
          cycle_color?: string
          cycle_end?: string | null
          cycle_label: string
          cycle_start: string
          is_current?: boolean
          sort_order?: number
        }
        Update: {
          created_at?: string
          cycle_abbr?: string
          cycle_code?: string
          cycle_color?: string
          cycle_end?: string | null
          cycle_label?: string
          cycle_start?: string
          is_current?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      data_quality_audit_snapshots: {
        Row: {
          audit_result: Json
          created_at: string
          created_by: string | null
          flag_count: number
          id: string
          issue_count: number
          run_context: string
          run_label: string | null
          source_batch_id: string | null
        }
        Insert: {
          audit_result: Json
          created_at?: string
          created_by?: string | null
          flag_count?: number
          id?: string
          issue_count?: number
          run_context?: string
          run_label?: string | null
          source_batch_id?: string | null
        }
        Update: {
          audit_result?: Json
          created_at?: string
          created_by?: string | null
          flag_count?: number
          id?: string
          issue_count?: number
          run_context?: string
          run_label?: string | null
          source_batch_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_source_batch_id_fkey"
            columns: ["source_batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          audience_level: string | null
          calendar_event_id: string | null
          created_at: string | null
          created_by: string | null
          curation_status: string
          date: string
          duration_actual: number | null
          duration_minutes: number
          id: string
          is_recorded: boolean | null
          meeting_link: string | null
          recurrence_group: string | null
          source: string | null
          title: string
          tribe_id: number | null
          type: string
          updated_at: string | null
          youtube_url: string | null
        }
        Insert: {
          audience_level?: string | null
          calendar_event_id?: string | null
          created_at?: string | null
          created_by?: string | null
          curation_status?: string
          date: string
          duration_actual?: number | null
          duration_minutes?: number
          id?: string
          is_recorded?: boolean | null
          meeting_link?: string | null
          recurrence_group?: string | null
          source?: string | null
          title: string
          tribe_id?: number | null
          type: string
          updated_at?: string | null
          youtube_url?: string | null
        }
        Update: {
          audience_level?: string | null
          calendar_event_id?: string | null
          created_at?: string | null
          created_by?: string | null
          curation_status?: string
          date?: string
          duration_actual?: number | null
          duration_minutes?: number
          id?: string
          is_recorded?: boolean | null
          meeting_link?: string | null
          recurrence_group?: string | null
          source?: string | null
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
      governance_bundle_snapshots: {
        Row: {
          context_label: string | null
          created_at: string
          created_by: string | null
          id: string
          payload: Json
          window_days: number
        }
        Insert: {
          context_label?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          payload: Json
          window_days: number
        }
        Update: {
          context_label?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          payload?: Json
          window_days?: number
        }
        Relationships: [
          {
            foreignKeyName: "governance_bundle_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "governance_bundle_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "governance_bundle_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_bundle_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
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
      hub_resources: {
        Row: {
          asset_type: string
          author_id: string | null
          course_id: number | null
          created_at: string
          curation_status: string
          cycle_code: string | null
          description: string | null
          id: string
          is_active: boolean
          source: string | null
          tags: string[] | null
          title: string
          trello_card_id: string | null
          tribe_id: number | null
          updated_at: string
          url: string | null
        }
        Insert: {
          asset_type: string
          author_id?: string | null
          course_id?: number | null
          created_at?: string
          curation_status?: string
          cycle_code?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          source?: string | null
          tags?: string[] | null
          title: string
          trello_card_id?: string | null
          tribe_id?: number | null
          updated_at?: string
          url?: string | null
        }
        Update: {
          asset_type?: string
          author_id?: string | null
          course_id?: number | null
          created_at?: string
          curation_status?: string
          cycle_code?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          source?: string | null
          tags?: string[] | null
          title?: string
          trello_card_id?: string | null
          tribe_id?: number | null
          updated_at?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_alert_events: {
        Row: {
          alert_id: number
          changed_at: string
          changed_by: string | null
          from_status: string | null
          id: number
          metadata: Json
          reason: string | null
          to_status: string
        }
        Insert: {
          alert_id: number
          changed_at?: string
          changed_by?: string | null
          from_status?: string | null
          id?: number
          metadata?: Json
          reason?: string | null
          to_status: string
        }
        Update: {
          alert_id?: number
          changed_at?: string
          changed_by?: string | null
          from_status?: string | null
          id?: number
          metadata?: Json
          reason?: string | null
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_alert_events_alert_id_fkey"
            columns: ["alert_id"]
            isOneToOne: false
            referencedRelation: "ingestion_alerts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alert_events_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_events_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_events_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alert_events_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_alert_remediation_rules: {
        Row: {
          action_type: string
          alert_key: string
          enabled: boolean
          max_attempts: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          action_type?: string
          alert_key: string
          enabled?: boolean
          max_attempts?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          action_type?: string
          alert_key?: string
          enabled?: boolean
          max_attempts?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_alert_remediation_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_alert_remediation_runs: {
        Row: {
          action_type: string
          alert_id: number
          alert_key: string
          attempt: number
          created_at: string
          created_by: string | null
          details: Json
          id: number
          status: string
        }
        Insert: {
          action_type: string
          alert_id: number
          alert_key: string
          attempt: number
          created_at?: string
          created_by?: string | null
          details?: Json
          id?: number
          status: string
        }
        Update: {
          action_type?: string
          alert_id?: number
          alert_key?: string
          attempt?: number
          created_at?: string
          created_by?: string | null
          details?: Json
          id?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_alert_remediation_runs_alert_id_fkey"
            columns: ["alert_id"]
            isOneToOne: false
            referencedRelation: "ingestion_alerts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_runs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_runs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_runs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alert_remediation_runs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_alerts: {
        Row: {
          alert_key: string
          batch_id: string | null
          created_by: string | null
          details: Json
          detected_at: string
          id: number
          resolved_at: string | null
          severity: string
          status: string
          summary: string
        }
        Insert: {
          alert_key: string
          batch_id?: string | null
          created_by?: string | null
          details?: Json
          detected_at?: string
          id?: number
          resolved_at?: string | null
          severity: string
          status?: string
          summary: string
        }
        Update: {
          alert_key?: string
          batch_id?: string | null
          created_by?: string | null
          details?: Json
          detected_at?: string
          id?: number
          resolved_at?: string | null
          severity?: string
          status?: string
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_alerts_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alerts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alerts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_alerts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_alerts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_apply_locks: {
        Row: {
          acquired_at: string
          expires_at: string
          holder: string
          metadata: Json
          source: string
        }
        Insert: {
          acquired_at?: string
          expires_at: string
          holder: string
          metadata?: Json
          source: string
        }
        Update: {
          acquired_at?: string
          expires_at?: string
          holder?: string
          metadata?: Json
          source?: string
        }
        Relationships: []
      }
      ingestion_batch_files: {
        Row: {
          batch_id: string
          created_at: string
          file_hash: string | null
          file_path: string
          file_size_bytes: number | null
          id: number
          result: Json
          source_kind: string
          status: string
          updated_at: string
        }
        Insert: {
          batch_id: string
          created_at?: string
          file_hash?: string | null
          file_path: string
          file_size_bytes?: number | null
          id?: number
          result?: Json
          source_kind: string
          status?: string
          updated_at?: string
        }
        Update: {
          batch_id?: string
          created_at?: string
          file_hash?: string | null
          file_path?: string
          file_size_bytes?: number | null
          id?: number
          result?: Json
          source_kind?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_batch_files_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_batches: {
        Row: {
          finished_at: string | null
          id: string
          initiated_by: string | null
          mode: string
          notes: string | null
          source: string
          started_at: string
          status: string
          summary: Json
        }
        Insert: {
          finished_at?: string | null
          id?: string
          initiated_by?: string | null
          mode?: string
          notes?: string | null
          source: string
          started_at?: string
          status?: string
          summary?: Json
        }
        Update: {
          finished_at?: string | null
          id?: string
          initiated_by?: string | null
          mode?: string
          notes?: string | null
          source?: string
          started_at?: string
          status?: string
          summary?: Json
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_batches_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_batches_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_batches_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_batches_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_provenance_signatures: {
        Row: {
          batch_id: string
          file_hash: string
          file_path: string
          id: number
          metadata: Json
          signature: string
          signed_at: string
          signed_by: string | null
          source_kind: string
        }
        Insert: {
          batch_id: string
          file_hash: string
          file_path: string
          id?: number
          metadata?: Json
          signature: string
          signed_at?: string
          signed_by?: string | null
          source_kind: string
        }
        Update: {
          batch_id?: string
          file_hash?: string
          file_path?: string
          id?: number
          metadata?: Json
          signature?: string
          signed_at?: string
          signed_by?: string | null
          source_kind?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_provenance_signatures_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_provenance_signatures_signed_by_fkey"
            columns: ["signed_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_provenance_signatures_signed_by_fkey"
            columns: ["signed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_provenance_signatures_signed_by_fkey"
            columns: ["signed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_provenance_signatures_signed_by_fkey"
            columns: ["signed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_remediation_escalation_matrix: {
        Row: {
          action_type: string
          enabled: boolean
          priority: number
          recurrence_threshold: number
          severity: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          action_type: string
          enabled?: boolean
          priority?: number
          recurrence_threshold: number
          severity: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          action_type?: string
          enabled?: boolean
          priority?: number
          recurrence_threshold?: number
          severity?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_rollback_plans: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          batch_id: string | null
          created_at: string
          created_by: string | null
          details: Json
          dry_run: boolean
          executed_at: string | null
          executed_by: string | null
          execution_window_end: string | null
          execution_window_start: string | null
          id: string
          reason: string
          second_approved_at: string | null
          second_approved_by: string | null
          status: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          details?: Json
          dry_run?: boolean
          executed_at?: string | null
          executed_by?: string | null
          execution_window_end?: string | null
          execution_window_start?: string | null
          id?: string
          reason: string
          second_approved_at?: string | null
          second_approved_by?: string | null
          status?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          details?: Json
          dry_run?: boolean
          executed_at?: string | null
          executed_by?: string | null
          execution_window_end?: string | null
          execution_window_start?: string | null
          id?: string
          reason?: string
          second_approved_at?: string | null
          second_approved_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_rollback_plans_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_executed_by_fkey"
            columns: ["executed_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_executed_by_fkey"
            columns: ["executed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_executed_by_fkey"
            columns: ["executed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_executed_by_fkey"
            columns: ["executed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_second_approved_by_fkey"
            columns: ["second_approved_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_second_approved_by_fkey"
            columns: ["second_approved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_second_approved_by_fkey"
            columns: ["second_approved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_rollback_plans_second_approved_by_fkey"
            columns: ["second_approved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_run_ledger: {
        Row: {
          batch_id: string | null
          created_at: string
          created_by: string | null
          id: string
          manifest_hash: string
          mode: string
          run_key: string
          run_notes: string | null
          source: string
          status: string
          updated_at: string
        }
        Insert: {
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          manifest_hash: string
          mode: string
          run_key: string
          run_notes?: string | null
          source: string
          status?: string
          updated_at?: string
        }
        Update: {
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          manifest_hash?: string
          mode?: string
          run_key?: string
          run_notes?: string | null
          source?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_run_ledger_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_run_ledger_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_run_ledger_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_run_ledger_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_run_ledger_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_source_controls: {
        Row: {
          allow_apply: boolean
          notes: string | null
          require_manual_review: boolean
          source: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allow_apply?: boolean
          notes?: string | null
          require_manual_review?: boolean
          source: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allow_apply?: boolean
          notes?: string | null
          require_manual_review?: boolean
          source?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_source_sla: {
        Row: {
          enabled: boolean
          escalation_severity: string
          expected_max_minutes: number
          source: string
          timeout_minutes: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          enabled?: boolean
          escalation_severity?: string
          expected_max_minutes?: number
          source: string
          timeout_minutes?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          enabled?: boolean
          escalation_severity?: string
          expected_max_minutes?: number
          source?: string
          timeout_minutes?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
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
      legacy_member_links: {
        Row: {
          chapter_snapshot: string | null
          confidence_score: number
          created_at: string
          created_by: string | null
          cycle_code: string
          id: number
          legacy_tribe_id: number
          link_type: string
          member_id: string
          metadata: Json
          role_snapshot: string | null
          updated_at: string
        }
        Insert: {
          chapter_snapshot?: string | null
          confidence_score?: number
          created_at?: string
          created_by?: string | null
          cycle_code: string
          id?: number
          legacy_tribe_id: number
          link_type?: string
          member_id: string
          metadata?: Json
          role_snapshot?: string | null
          updated_at?: string
        }
        Update: {
          chapter_snapshot?: string | null
          confidence_score?: number
          created_at?: string
          created_by?: string | null
          cycle_code?: string
          id?: number
          legacy_tribe_id?: number
          link_type?: string
          member_id?: string
          metadata?: Json
          role_snapshot?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "legacy_member_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_member_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_member_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_member_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_member_links_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "legacy_tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_member_links_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_member_links_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_member_links_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_member_links_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      legacy_tribe_board_links: {
        Row: {
          board_id: string
          confidence_score: number
          created_at: string
          id: number
          legacy_tribe_id: number
          metadata: Json
          notes: string | null
          relation_type: string
          updated_at: string
        }
        Insert: {
          board_id: string
          confidence_score?: number
          created_at?: string
          id?: number
          legacy_tribe_id: number
          metadata?: Json
          notes?: string | null
          relation_type?: string
          updated_at?: string
        }
        Update: {
          board_id?: string
          confidence_score?: number
          created_at?: string
          id?: number
          legacy_tribe_id?: number
          metadata?: Json
          notes?: string | null
          relation_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "legacy_tribe_board_links_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_tribe_board_links_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "legacy_tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      legacy_tribes: {
        Row: {
          chapter: string | null
          created_at: string
          created_by: string | null
          cycle_code: string
          cycle_label: string | null
          display_name: string
          id: number
          legacy_key: string
          metadata: Json
          notes: string | null
          quadrant: number | null
          status: string
          tribe_id: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          chapter?: string | null
          created_at?: string
          created_by?: string | null
          cycle_code: string
          cycle_label?: string | null
          display_name: string
          id?: number
          legacy_key: string
          metadata?: Json
          notes?: string | null
          quadrant?: number | null
          status?: string
          tribe_id?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          chapter?: string | null
          created_at?: string
          created_by?: string | null
          cycle_code?: string
          cycle_label?: string | null
          display_name?: string
          id?: number
          legacy_key?: string
          metadata?: Json
          notes?: string | null
          quadrant?: number | null
          status?: string
          tribe_id?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legacy_tribes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_tribes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_tribes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_tribes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_tribes_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "legacy_tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legacy_tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      meeting_artifacts: {
        Row: {
          agenda_items: string[] | null
          created_at: string
          created_by: string | null
          cycle_code: string | null
          deliberations: string[] | null
          event_id: string | null
          id: string
          is_published: boolean
          meeting_date: string
          page_data_snapshot: Json | null
          recording_url: string | null
          title: string
          tribe_id: number | null
          updated_at: string
        }
        Insert: {
          agenda_items?: string[] | null
          created_at?: string
          created_by?: string | null
          cycle_code?: string | null
          deliberations?: string[] | null
          event_id?: string | null
          id?: string
          is_published?: boolean
          meeting_date: string
          page_data_snapshot?: Json | null
          recording_url?: string | null
          title: string
          tribe_id?: number | null
          updated_at?: string
        }
        Update: {
          agenda_items?: string[] | null
          created_at?: string
          created_by?: string | null
          cycle_code?: string | null
          deliberations?: string[] | null
          event_id?: string | null
          id?: string
          is_published?: boolean
          meeting_date?: string
          page_data_snapshot?: Json | null
          recording_url?: string | null
          title?: string
          tribe_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
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
          share_whatsapp: boolean
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
          share_whatsapp?: boolean
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
          share_whatsapp?: boolean
          state?: string | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Relationships: []
      }
      notion_import_staging: {
        Row: {
          assignee_name: string | null
          batch_id: string | null
          chapter_hint: string | null
          confidence_score: number
          created_at: string
          description: string | null
          due_date: string | null
          external_item_id: string | null
          id: number
          mapped_at: string | null
          mapped_board_id: string | null
          mapped_item_id: string | null
          normalized: Json
          source_file: string
          source_page: string | null
          status_raw: string | null
          tags: string[]
          title: string
          tribe_hint: string | null
          updated_at: string
        }
        Insert: {
          assignee_name?: string | null
          batch_id?: string | null
          chapter_hint?: string | null
          confidence_score?: number
          created_at?: string
          description?: string | null
          due_date?: string | null
          external_item_id?: string | null
          id?: number
          mapped_at?: string | null
          mapped_board_id?: string | null
          mapped_item_id?: string | null
          normalized?: Json
          source_file: string
          source_page?: string | null
          status_raw?: string | null
          tags?: string[]
          title: string
          tribe_hint?: string | null
          updated_at?: string
        }
        Update: {
          assignee_name?: string | null
          batch_id?: string | null
          chapter_hint?: string | null
          confidence_score?: number
          created_at?: string
          description?: string | null
          due_date?: string | null
          external_item_id?: string | null
          id?: number
          mapped_at?: string | null
          mapped_board_id?: string | null
          mapped_item_id?: string | null
          normalized?: Json
          source_file?: string
          source_page?: string | null
          status_raw?: string | null
          tags?: string[]
          title?: string
          tribe_hint?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notion_import_staging_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "ingestion_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notion_import_staging_mapped_board_id_fkey"
            columns: ["mapped_board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notion_import_staging_mapped_item_id_fkey"
            columns: ["mapped_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
        ]
      }
      portfolio_data_sanity_runs: {
        Row: {
          created_at: string
          id: number
          run_by: string
          summary: Json
        }
        Insert: {
          created_at?: string
          id?: never
          run_by: string
          summary?: Json
        }
        Update: {
          created_at?: string
          id?: never
          run_by?: string
          summary?: Json
        }
        Relationships: [
          {
            foreignKeyName: "portfolio_data_sanity_runs_run_by_fkey"
            columns: ["run_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "portfolio_data_sanity_runs_run_by_fkey"
            columns: ["run_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "portfolio_data_sanity_runs_run_by_fkey"
            columns: ["run_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "portfolio_data_sanity_runs_run_by_fkey"
            columns: ["run_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
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
      project_boards: {
        Row: {
          board_name: string
          board_scope: string
          columns: Json
          created_at: string
          created_by: string | null
          cycle_scope: string | null
          domain_key: string | null
          id: string
          is_active: boolean
          source: string
          tribe_id: number | null
          updated_at: string
        }
        Insert: {
          board_name: string
          board_scope?: string
          columns?: Json
          created_at?: string
          created_by?: string | null
          cycle_scope?: string | null
          domain_key?: string | null
          id?: string
          is_active?: boolean
          source?: string
          tribe_id?: number | null
          updated_at?: string
        }
        Update: {
          board_name?: string
          board_scope?: string
          columns?: Json
          created_at?: string
          created_by?: string | null
          cycle_scope?: string | null
          domain_key?: string | null
          id?: string
          is_active?: boolean
          source?: string
          tribe_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_submission_events: {
        Row: {
          board_item_id: string
          channel: string
          created_at: string
          external_link: string | null
          id: number
          notes: string | null
          outcome: string
          published_at: string | null
          submitted_at: string | null
          updated_at: string
          updated_by: string
        }
        Insert: {
          board_item_id: string
          channel?: string
          created_at?: string
          external_link?: string | null
          id?: never
          notes?: string | null
          outcome?: string
          published_at?: string | null
          submitted_at?: string | null
          updated_at?: string
          updated_by: string
        }
        Update: {
          board_item_id?: string
          channel?: string
          created_at?: string
          external_link?: string | null
          id?: never
          notes?: string | null
          outcome?: string
          published_at?: string | null
          submitted_at?: string | null
          updated_at?: string
          updated_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_submission_events_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      readiness_slo_alerts: {
        Row: {
          breach_key: string
          created_at: string
          details: Json
          id: number
          resolved_at: string | null
          status: string
        }
        Insert: {
          breach_key: string
          created_at?: string
          details?: Json
          id?: number
          resolved_at?: string | null
          status?: string
        }
        Update: {
          breach_key?: string
          created_at?: string
          details?: Json
          id?: number
          resolved_at?: string | null
          status?: string
        }
        Relationships: []
      }
      release_readiness_history: {
        Row: {
          context_label: string | null
          created_at: string
          created_by: string | null
          id: string
          mode: string
          open_alerts: Json
          ready: boolean
          reasons: Json
          snapshot: Json | null
          thresholds: Json
        }
        Insert: {
          context_label?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          mode: string
          open_alerts?: Json
          ready: boolean
          reasons?: Json
          snapshot?: Json | null
          thresholds?: Json
        }
        Update: {
          context_label?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          mode?: string
          open_alerts?: Json
          ready?: boolean
          reasons?: Json
          snapshot?: Json | null
          thresholds?: Json
        }
        Relationships: [
          {
            foreignKeyName: "release_readiness_history_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "release_readiness_history_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "release_readiness_history_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "release_readiness_history_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      release_readiness_policies: {
        Row: {
          max_open_warnings: number
          mode: string
          policy_key: string
          require_fresh_snapshot_hours: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          max_open_warnings?: number
          mode: string
          policy_key: string
          require_fresh_snapshot_hours?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          max_open_warnings?: number
          mode?: string
          policy_key?: string
          require_fresh_snapshot_hours?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      rollback_audit_events: {
        Row: {
          actor_id: string | null
          created_at: string
          details: Json
          event_type: string
          id: number
          plan_id: string
          reason: string | null
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          details?: Json
          event_type: string
          id?: number
          plan_id: string
          reason?: string | null
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          details?: Json
          event_type?: string
          id?: number
          plan_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "rollback_audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "rollback_audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "rollback_audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rollback_audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rollback_audit_events_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "ingestion_rollback_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      site_config: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      taxonomy_tags: {
        Row: {
          category: string
          id: number
          is_active: boolean
          kpi_ref: string | null
          label_en: string
          label_es: string
          label_pt: string
          tag_key: string
        }
        Insert: {
          category: string
          id?: number
          is_active?: boolean
          kpi_ref?: string | null
          label_en?: string
          label_es?: string
          label_pt: string
          tag_key: string
        }
        Update: {
          category?: string
          id?: number
          is_active?: boolean
          kpi_ref?: string | null
          label_en?: string
          label_es?: string
          label_pt?: string
          tag_key?: string
        }
        Relationships: []
      }
      trello_import_log: {
        Row: {
          board_name: string
          board_source: string
          cards_mapped: number
          cards_skipped: number
          cards_total: number
          id: number
          imported_at: string
          imported_by: string | null
          notes: string | null
          target_table: string
        }
        Insert: {
          board_name: string
          board_source: string
          cards_mapped?: number
          cards_skipped?: number
          cards_total?: number
          id?: number
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          target_table: string
        }
        Update: {
          board_name?: string
          board_source?: string
          cards_mapped?: number
          cards_skipped?: number
          cards_total?: number
          id?: number
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          target_table?: string
        }
        Relationships: []
      }
      tribe_continuity_overrides: {
        Row: {
          continuity_key: string
          continuity_type: string
          created_at: string
          current_cycle_code: string
          current_tribe_id: number | null
          id: number
          is_active: boolean
          leader_name: string | null
          legacy_cycle_code: string
          legacy_tribe_id: number | null
          metadata: Json
          notes: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          continuity_key: string
          continuity_type?: string
          created_at?: string
          current_cycle_code: string
          current_tribe_id?: number | null
          id?: number
          is_active?: boolean
          leader_name?: string | null
          legacy_cycle_code: string
          legacy_tribe_id?: number | null
          metadata?: Json
          notes?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          continuity_key?: string
          continuity_type?: string
          created_at?: string
          current_cycle_code?: string
          current_tribe_id?: number | null
          id?: number
          is_active?: boolean
          leader_name?: string | null
          legacy_cycle_code?: string
          legacy_tribe_id?: number | null
          metadata?: Json
          notes?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_continuity_overrides_current_tribe_id_fkey"
            columns: ["current_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_deliverables: {
        Row: {
          artifact_id: string | null
          assigned_member_id: string | null
          created_at: string
          cycle_code: string
          description: string | null
          due_date: string | null
          id: string
          status: string
          title: string
          tribe_id: number
          updated_at: string
        }
        Insert: {
          artifact_id?: string | null
          assigned_member_id?: string | null
          created_at?: string
          cycle_code: string
          description?: string | null
          due_date?: string | null
          id?: string
          status?: string
          title: string
          tribe_id: number
          updated_at?: string
        }
        Update: {
          artifact_id?: string | null
          assigned_member_id?: string | null
          created_at?: string
          cycle_code?: string
          description?: string | null
          due_date?: string | null
          id?: string
          status?: string
          title?: string
          tribe_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tribe_deliverables_artifact_id_fkey"
            columns: ["artifact_id"]
            isOneToOne: false
            referencedRelation: "artifacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_cycle_code_fkey"
            columns: ["cycle_code"]
            isOneToOne: false
            referencedRelation: "cycles"
            referencedColumns: ["cycle_code"]
          },
          {
            foreignKeyName: "tribe_deliverables_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_lineage: {
        Row: {
          created_at: string
          created_by: string | null
          current_tribe_id: number
          cycle_scope: string | null
          id: number
          is_active: boolean
          legacy_tribe_id: number
          metadata: Json
          notes: string | null
          relation_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          current_tribe_id: number
          cycle_scope?: string | null
          id?: number
          is_active?: boolean
          legacy_tribe_id: number
          metadata?: Json
          notes?: string | null
          relation_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          current_tribe_id?: number
          cycle_scope?: string | null
          id?: number
          is_active?: boolean
          legacy_tribe_id?: number
          metadata?: Json
          notes?: string | null
          relation_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_current_tribe_id_fkey"
            columns: ["current_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
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
          is_active: boolean
          leader_member_id: string | null
          legacy_board_url: string | null
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
          workstream_type: string
        }
        Insert: {
          drive_url?: string | null
          id: number
          is_active?: boolean
          leader_member_id?: string | null
          legacy_board_url?: string | null
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
          workstream_type?: string
        }
        Update: {
          drive_url?: string | null
          id?: number
          is_active?: boolean
          leader_member_id?: string | null
          legacy_board_url?: string | null
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
          workstream_type?: string
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
      volunteer_applications: {
        Row: {
          app_status: string | null
          application_id: string
          areas_of_interest: string | null
          certifications: string[] | null
          city: string | null
          country: string | null
          created_at: string
          cycle: number
          email: string
          essay_answers: Json | null
          first_name: string
          id: string
          industry: string | null
          is_existing_member: boolean
          label: string | null
          last_name: string
          member_id: string | null
          membership_status: string | null
          opportunity_id: string | null
          pmi_id: string | null
          reason_for_applying: string | null
          resume_url: string | null
          snapshot_date: string
          specialty: string | null
          state: string | null
        }
        Insert: {
          app_status?: string | null
          application_id: string
          areas_of_interest?: string | null
          certifications?: string[] | null
          city?: string | null
          country?: string | null
          created_at?: string
          cycle: number
          email: string
          essay_answers?: Json | null
          first_name: string
          id?: string
          industry?: string | null
          is_existing_member?: boolean
          label?: string | null
          last_name: string
          member_id?: string | null
          membership_status?: string | null
          opportunity_id?: string | null
          pmi_id?: string | null
          reason_for_applying?: string | null
          resume_url?: string | null
          snapshot_date: string
          specialty?: string | null
          state?: string | null
        }
        Update: {
          app_status?: string | null
          application_id?: string
          areas_of_interest?: string | null
          certifications?: string[] | null
          city?: string | null
          country?: string | null
          created_at?: string
          cycle?: number
          email?: string
          essay_answers?: Json | null
          first_name?: string
          id?: string
          industry?: string | null
          is_existing_member?: boolean
          label?: string | null
          last_name?: string
          member_id?: string | null
          membership_status?: string | null
          opportunity_id?: string | null
          pmi_id?: string | null
          reason_for_applying?: string | null
          resume_url?: string | null
          snapshot_date?: string
          specialty?: string | null
          state?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      webinars: {
        Row: {
          chapter_code: string
          created_at: string
          created_by: string | null
          description: string | null
          duration_min: number
          id: string
          meeting_link: string | null
          notes: string | null
          organizer_id: string | null
          scheduled_at: string
          status: string
          title: string
          tribe_id: number | null
          updated_at: string
          youtube_url: string | null
        }
        Insert: {
          chapter_code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          duration_min?: number
          id?: string
          meeting_link?: string | null
          notes?: string | null
          organizer_id?: string | null
          scheduled_at: string
          status?: string
          title: string
          tribe_id?: number | null
          updated_at?: string
          youtube_url?: string | null
        }
        Update: {
          chapter_code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          duration_min?: number
          id?: string
          meeting_link?: string | null
          notes?: string | null
          organizer_id?: string | null
          scheduled_at?: string
          status?: string
          title?: string
          tribe_id?: number | null
          updated_at?: string
          youtube_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "gamification_leaderboard"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
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
          cycle_artifact_points: number | null
          cycle_attendance_points: number | null
          cycle_bonus_points: number | null
          cycle_course_points: number | null
          cycle_points: number | null
          designations: string[] | null
          member_id: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
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
          id: string | null
          is_active: boolean | null
          linkedin_url: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          share_whatsapp: boolean | null
          state: string | null
          tribe_id: number | null
        }
        Insert: {
          chapter?: string | null
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
          id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          share_whatsapp?: boolean | null
          state?: string | null
          tribe_id?: number | null
        }
        Update: {
          chapter?: string | null
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
          id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          share_whatsapp?: boolean | null
          state?: string | null
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
      admin_acquire_ingestion_apply_lock: {
        Args: {
          p_holder: string
          p_metadata?: Json
          p_source: string
          p_ttl_minutes?: number
        }
        Returns: Json
      }
      admin_append_rollback_audit_event: {
        Args: {
          p_details?: Json
          p_event_type: string
          p_plan_id: string
          p_reason?: string
        }
        Returns: Json
      }
      admin_approve_ingestion_rollback: {
        Args: {
          p_execution_window_end?: string
          p_execution_window_start?: string
          p_plan_id: string
        }
        Returns: Json
      }
      admin_archive_board_item: {
        Args: { p_item_id: string; p_reason?: string }
        Returns: Json
      }
      admin_archive_project_board: {
        Args: {
          p_archive_items?: boolean
          p_board_id: string
          p_reason?: string
        }
        Returns: Json
      }
      admin_capture_data_quality_snapshot: {
        Args: {
          p_run_context?: string
          p_run_label?: string
          p_source_batch_id?: string
        }
        Returns: Json
      }
      admin_capture_governance_bundle_snapshot: {
        Args: { p_context_label?: string; p_window_days?: number }
        Returns: Json
      }
      admin_change_tribe_leader: {
        Args: { p_new_leader_id: string; p_reason?: string; p_tribe_id: number }
        Returns: Json
      }
      admin_check_ingestion_source_timeout: {
        Args: { p_source: string; p_started_at: string }
        Returns: Json
      }
      admin_check_readiness_slo_breach: {
        Args: {
          p_max_consecutive_not_ready?: number
          p_max_hours_since_last_decision?: number
        }
        Returns: Json
      }
      admin_complete_ingestion_run: {
        Args: {
          p_batch_id?: string
          p_notes?: string
          p_run_id: string
          p_status: string
        }
        Returns: Json
      }
      admin_data_quality_audit: { Args: never; Returns: Json }
      admin_deactivate_member: {
        Args: { p_member_id: string; p_reason?: string }
        Returns: Json
      }
      admin_deactivate_tribe: {
        Args: { p_reason?: string; p_tribe_id: number }
        Returns: Json
      }
      admin_detect_board_taxonomy_drift: { Args: never; Returns: Json }
      admin_ensure_communication_tribe: {
        Args: {
          p_name?: string
          p_notes?: string
          p_quadrant?: number
          p_quadrant_name?: string
        }
        Returns: Json
      }
      admin_execute_ingestion_rollback: {
        Args: { p_approve_and_execute?: boolean; p_plan_id: string }
        Returns: Json
      }
      admin_finalize_ingestion_batch: {
        Args: { p_batch_id: string; p_status?: string; p_summary?: Json }
        Returns: Json
      }
      admin_force_tribe_selection: {
        Args: { p_member_id: string; p_tribe_id: number }
        Returns: Json
      }
      admin_get_ingestion_source_policy: {
        Args: { p_source: string }
        Returns: Json
      }
      admin_get_tribe_allocations: { Args: never; Returns: Json }
      admin_inactivate_member: {
        Args: { p_member_id: string; p_reason?: string }
        Returns: Json
      }
      admin_link_board_to_legacy_tribe: {
        Args: {
          p_board_id: string
          p_confidence_score?: number
          p_legacy_tribe_id: number
          p_metadata?: Json
          p_notes?: string
          p_relation_type?: string
        }
        Returns: Json
      }
      admin_link_communication_boards: {
        Args: { p_tribe_id?: number }
        Returns: Json
      }
      admin_link_member_to_legacy_tribe: {
        Args: {
          p_chapter_snapshot?: string
          p_confidence_score?: number
          p_cycle_code: string
          p_legacy_tribe_id: number
          p_link_type?: string
          p_member_id: string
          p_metadata?: Json
          p_role_snapshot?: string
        }
        Returns: Json
      }
      admin_list_archived_board_items: {
        Args: { p_board_id?: string; p_limit?: number }
        Returns: {
          assignee_name: string
          board_id: string
          board_name: string
          board_scope: string
          domain_key: string
          due_date: string
          id: string
          title: string
          updated_at: string
        }[]
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
      admin_list_tribe_lineage: {
        Args: { p_include_inactive?: boolean }
        Returns: {
          current_tribe_id: number
          current_tribe_name: string
          cycle_scope: string
          id: number
          is_active: boolean
          legacy_tribe_id: number
          legacy_tribe_name: string
          metadata: Json
          notes: string
          relation_type: string
          updated_at: string
        }[]
      }
      admin_list_tribes: {
        Args: { p_include_inactive?: boolean }
        Returns: {
          active_members: number
          id: number
          is_active: boolean
          leader_member_id: string
          leader_name: string
          name: string
          quadrant: number
          quadrant_name: string
          total_members: number
        }[]
      }
      admin_map_notion_item_to_board: {
        Args: {
          p_apply_insert?: boolean
          p_board_id: string
          p_position?: number
          p_staging_id: number
          p_status?: string
        }
        Returns: Json
      }
      admin_move_member_tribe: {
        Args: { p_member_id: string; p_new_tribe_id: number; p_reason?: string }
        Returns: Json
      }
      admin_plan_ingestion_rollback: {
        Args: {
          p_batch_id: string
          p_details?: Json
          p_dry_run?: boolean
          p_reason: string
        }
        Returns: Json
      }
      admin_raise_provenance_anomaly_alert: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      admin_reactivate_member: { Args: { p_member_id: string }; Returns: Json }
      admin_record_release_readiness_decision: {
        Args: { p_context_label?: string; p_mode?: string }
        Returns: Json
      }
      admin_register_ingestion_run: {
        Args: {
          p_manifest_hash: string
          p_mode: string
          p_notes?: string
          p_run_key: string
          p_source: string
        }
        Returns: Json
      }
      admin_release_ingestion_apply_lock: {
        Args: { p_holder: string; p_source: string }
        Returns: Json
      }
      admin_release_readiness_gate: {
        Args: {
          p_max_open_warnings?: number
          p_policy_mode?: string
          p_require_fresh_snapshot_hours?: number
        }
        Returns: Json
      }
      admin_remove_tribe_selection: {
        Args: { p_member_id: string }
        Returns: Json
      }
      admin_resolve_remediation_action: {
        Args: { p_alert_id: number }
        Returns: Json
      }
      admin_restore_board_item: {
        Args: {
          p_item_id: string
          p_reason?: string
          p_restore_status?: string
        }
        Returns: Json
      }
      admin_restore_project_board: {
        Args: { p_board_id: string; p_reason?: string }
        Returns: Json
      }
      admin_run_dry_rehearsal_chain: {
        Args: { p_context_label?: string; p_gate_mode?: string }
        Returns: Json
      }
      admin_run_ingestion_alert_remediation: {
        Args: { p_alert_id: number }
        Returns: Json
      }
      admin_run_portfolio_data_sanity: { Args: never; Returns: Json }
      admin_run_post_ingestion_chain: {
        Args: {
          p_batch_id?: string
          p_capture_snapshot?: boolean
          p_gate_mode?: string
        }
        Returns: Json
      }
      admin_run_post_ingestion_healthcheck: {
        Args: { p_batch_id?: string }
        Returns: Json
      }
      admin_set_ingestion_alert_remediation_rule: {
        Args: {
          p_action_type?: string
          p_alert_key: string
          p_enabled?: boolean
          p_max_attempts?: number
        }
        Returns: Json
      }
      admin_set_ingestion_source_policy: {
        Args: {
          p_allow_apply: boolean
          p_notes?: string
          p_require_manual_review?: boolean
          p_source: string
        }
        Returns: Json
      }
      admin_set_ingestion_source_sla: {
        Args: {
          p_enabled?: boolean
          p_escalation_severity?: string
          p_expected_max_minutes?: number
          p_source: string
          p_timeout_minutes?: number
        }
        Returns: Json
      }
      admin_set_release_readiness_policy: {
        Args: {
          p_max_open_warnings?: number
          p_mode?: string
          p_policy_key?: string
          p_require_fresh_snapshot_hours?: number
        }
        Returns: Json
      }
      admin_set_tribe_active: {
        Args: { p_is_active: boolean; p_reason?: string; p_tribe_id: number }
        Returns: Json
      }
      admin_sign_ingestion_file_provenance: {
        Args: {
          p_batch_id: string
          p_file_hash: string
          p_file_path: string
          p_metadata?: Json
          p_source_kind: string
        }
        Returns: Json
      }
      admin_simulate_ingestion_rollback: {
        Args: { p_plan_id: string }
        Returns: Json
      }
      admin_start_ingestion_batch: {
        Args: { p_mode?: string; p_notes?: string; p_source: string }
        Returns: string
      }
      admin_suggest_notion_board_mappings: {
        Args: { p_limit?: number; p_only_unmapped?: boolean }
        Returns: {
          confidence_score: number
          notion_item_id: number
          reason: string
          suggested_board_id: string
          suggested_board_name: string
        }[]
      }
      admin_update_ingestion_alert_status: {
        Args: {
          p_alert_id: number
          p_metadata?: Json
          p_next_status: string
          p_reason?: string
        }
        Returns: Json
      }
      admin_update_member: {
        Args: {
          p_chapter?: string
          p_current_cycle_active?: boolean
          p_designations?: string[]
          p_email?: string
          p_linkedin_url?: string
          p_member_id: string
          p_name?: string
          p_operational_role?: string
          p_phone?: string
          p_pmi_id?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      admin_upsert_legacy_tribe: {
        Args: {
          p_chapter?: string
          p_cycle_code?: string
          p_cycle_label?: string
          p_display_name?: string
          p_id?: number
          p_legacy_key?: string
          p_metadata?: Json
          p_notes?: string
          p_quadrant?: number
          p_status?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      admin_upsert_tribe: {
        Args: {
          p_drive_url?: string
          p_id?: number
          p_is_active?: boolean
          p_leader_member_id?: string
          p_meeting_link?: string
          p_miro_url?: string
          p_name?: string
          p_notes?: string
          p_quadrant?: number
          p_quadrant_name?: string
          p_whatsapp_url?: string
        }
        Returns: Json
      }
      admin_upsert_tribe_continuity_override: {
        Args: {
          p_continuity_key: string
          p_continuity_type?: string
          p_current_cycle_code: string
          p_current_tribe_id: number
          p_is_active?: boolean
          p_leader_name?: string
          p_legacy_cycle_code: string
          p_legacy_tribe_id: number
          p_metadata?: Json
          p_notes?: string
        }
        Returns: Json
      }
      admin_upsert_tribe_lineage: {
        Args: {
          p_current_tribe_id?: number
          p_cycle_scope?: string
          p_id?: number
          p_is_active?: boolean
          p_legacy_tribe_id?: number
          p_metadata?: Json
          p_notes?: string
          p_relation_type?: string
        }
        Returns: Json
      }
      admin_verify_ingestion_provenance_batch: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      advance_board_item_curation: {
        Args: { p_action: string; p_item_id: string; p_reviewer_id?: string }
        Returns: undefined
      }
      analytics_is_leadership_role: {
        Args: { p_designations: string[]; p_operational_role: string }
        Returns: boolean
      }
      analytics_member_scope: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: {
          chapter: string
          cycle_code: string
          cycle_end: string
          cycle_label: string
          cycle_start: string
          first_cycle_code: string
          first_cycle_start: string
          is_current: boolean
          member_id: string
          tribe_id: number
        }[]
      }
      analytics_role_bucket: {
        Args: { p_designations: string[]; p_operational_role: string }
        Returns: string
      }
      broadcast_count_today: { Args: { p_tribe_id: number }; Returns: number }
      broadcast_history: {
        Args: { p_limit?: number; p_tribe_id?: number }
        Returns: {
          id: string
          recipient_count: number
          sent_at: string
          sent_by_name: string
          subject: string
          tribe_id: number
          tribe_name: string
        }[]
      }
      can_manage_comms_metrics: { Args: never; Returns: boolean }
      can_manage_knowledge: { Args: never; Returns: boolean }
      can_read_internal_analytics: { Args: never; Returns: boolean }
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
      count_tribe_slots: { Args: never; Returns: Json }
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
      curate_item: {
        Args: {
          p_action: string
          p_audience_level?: string
          p_id: string
          p_table: string
          p_tags?: string[]
          p_tribe_id?: number
        }
        Returns: Json
      }
      current_member_tier_rank: { Args: never; Returns: number }
      decrypt_sensitive: { Args: { val: string }; Returns: string }
      deselect_tribe: { Args: never; Returns: Json }
      encrypt_sensitive: { Args: { val: string }; Returns: string }
      enqueue_artifact_publication_card: {
        Args: { p_actor_member_id?: string; p_artifact_id: string }
        Returns: Json
      }
      exec_analytics_v2_quality: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
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
      exec_certification_delta: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_chapter_roi: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_funnel_summary: { Args: never; Returns: Json }
      exec_funnel_v2: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_governance_export_bundle: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_impact_hours_v2: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_partner_governance_scorecards: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_partner_governance_summary: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_partner_governance_trends: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_portfolio_board_summary: {
        Args: { p_include_inactive?: boolean }
        Returns: Json
      }
      exec_readiness_slo_by_source: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_readiness_slo_dashboard: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_remediation_effectiveness: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      exec_role_transitions: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_skills_radar: { Args: never; Returns: Json }
      get_comms_dashboard_metrics: { Args: never; Returns: Json }
      get_communication_template: {
        Args: { p_slug: string; p_vars?: Json }
        Returns: Json
      }
      get_current_cycle: { Args: never; Returns: Json }
      get_events_with_attendance: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_executive_kpis: { Args: never; Returns: Json }
      get_member_by_auth: { Args: never; Returns: Json }
      get_member_cycle_xp: { Args: { p_member_id: string }; Returns: Json }
      get_my_member_record: {
        Args: never
        Returns: {
          designations: string[]
          id: string
          is_superadmin: boolean
          operational_role: string
          tribe_id: number
        }[]
      }
      get_site_config: { Args: never; Returns: Json }
      get_tribe_counts: {
        Args: never
        Returns: {
          member_count: number
          tribe_id: number
        }[]
      }
      get_tribe_event_roster: { Args: { p_event_id: string }; Returns: Json }
      get_tribe_member_contacts: { Args: { p_tribe_id: number }; Returns: Json }
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
      kpi_summary: { Args: never; Returns: Json }
      list_admin_links: {
        Args: never
        Returns: {
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          icon: string | null
          id: number
          is_active: boolean
          sort_order: number | null
          title: string
          updated_at: string
          url: string
        }[]
        SetofOptions: {
          from: "*"
          to: "admin_links"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_board_items: {
        Args: { p_board_id: string; p_status?: string }
        Returns: Json[]
      }
      list_curation_board: { Args: { p_status?: string }; Returns: Json[] }
      list_curation_pending_board_items: { Args: never; Returns: Json[] }
      list_cycles: { Args: never; Returns: Json }
      list_meeting_artifacts: {
        Args: { p_limit?: number; p_tribe_id?: number }
        Returns: {
          agenda_items: string[] | null
          created_at: string
          created_by: string | null
          cycle_code: string | null
          deliberations: string[] | null
          event_id: string | null
          id: string
          is_published: boolean
          meeting_date: string
          page_data_snapshot: Json | null
          recording_url: string | null
          title: string
          tribe_id: number | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "meeting_artifacts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_pending_curation: { Args: { p_table?: string }; Returns: Json }
      list_project_boards: { Args: { p_tribe_id?: number }; Returns: Json[] }
      list_radar_global: {
        Args: { p_publications_limit?: number; p_webinars_limit?: number }
        Returns: Json
      }
      list_taxonomy_tags: {
        Args: never
        Returns: {
          category: string
          id: number
          is_active: boolean
          kpi_ref: string | null
          label_en: string
          label_es: string
          label_pt: string
          tag_key: string
        }[]
        SetofOptions: {
          from: "*"
          to: "taxonomy_tags"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_tribe_deliverables: {
        Args: { p_cycle_code?: string; p_tribe_id: number }
        Returns: {
          artifact_id: string | null
          assigned_member_id: string | null
          created_at: string
          cycle_code: string
          description: string | null
          due_date: string | null
          id: string
          status: string
          title: string
          tribe_id: number
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "tribe_deliverables"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_volunteer_applications: {
        Args: {
          p_cycle?: number
          p_limit?: number
          p_offset?: number
          p_search?: string
        }
        Returns: Json
      }
      list_webinars: {
        Args: { p_status?: string }
        Returns: {
          chapter_code: string
          created_at: string
          created_by: string | null
          description: string | null
          duration_min: number
          id: string
          meeting_link: string | null
          notes: string | null
          organizer_id: string | null
          scheduled_at: string
          status: string
          title: string
          tribe_id: number | null
          updated_at: string
          youtube_url: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "webinars"
          isOneToOne: false
          isSetofReturn: true
        }
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
        | {
            Args: {
              p_credly_url?: string
              p_linkedin_url?: string
              p_phone?: string
              p_pmi_id?: string
              p_share_whatsapp?: boolean
            }
            Returns: Json
          }
      move_board_item: {
        Args: { p_item_id: string; p_new_status: string; p_position?: number }
        Returns: undefined
      }
      move_board_item_to_board: {
        Args: {
          p_item_id: number
          p_reason?: string
          p_target_board_id: number
        }
        Returns: Json
      }
      platform_activity_summary: { Args: never; Returns: Json }
      publish_board_item_from_curation: {
        Args: { p_item_id: string }
        Returns: string
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
      resolve_whatsapp_link: { Args: { p_member_id: string }; Returns: Json }
      save_presentation_snapshot: {
        Args: {
          p_agenda_items?: string[]
          p_deliberations?: string[]
          p_event_id?: string
          p_is_published?: boolean
          p_meeting_date: string
          p_recording_url?: string
          p_snapshot?: Json
          p_title: string
          p_tribe_id?: number
        }
        Returns: string
      }
      search_knowledge: {
        Args: { search_term: string }
        Returns: {
          artifact_id: string
          asset_id: string
          chunk_id: string
          content_snippet: string
          theme_title: string
          tribe_name: string
        }[]
      }
      select_tribe: { Args: { p_tribe_id: number }; Returns: Json }
      set_progress: {
        Args: { p_code: string; p_email: string; p_status: string }
        Returns: undefined
      }
      set_site_config: {
        Args: { p_key: string; p_value: Json }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      suggest_tags: {
        Args: { p_cycle_code?: string; p_title: string; p_type?: string }
        Returns: string[]
      }
      sync_attendance_points: { Args: never; Returns: Json }
      title_case: { Args: { input: string }; Returns: string }
      tribe_impact_ranking: {
        Args: never
        Returns: {
          avg_attendance: number
          total_events: number
          total_hours: number
          tribe_id: number
          tribe_name: string
        }[]
      }
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
      upsert_board_item: {
        Args: {
          p_assignee_id?: string
          p_attachments?: Json
          p_board_id?: string
          p_checklist?: Json
          p_description?: string
          p_due_date?: string
          p_item_id?: string
          p_labels?: Json
          p_status?: string
          p_tags?: string[]
          p_title?: string
        }
        Returns: string
      }
      upsert_publication_submission_event:
        | {
            Args: {
              p_board_item_id: string
              p_channel?: string
              p_notes?: string
              p_outcome?: string
              p_submitted_at?: string
            }
            Returns: {
              board_item_id: string
              channel: string
              created_at: string
              external_link: string | null
              id: number
              notes: string | null
              outcome: string
              published_at: string | null
              submitted_at: string | null
              updated_at: string
              updated_by: string
            }
            SetofOptions: {
              from: "*"
              to: "publication_submission_events"
              isOneToOne: true
              isSetofReturn: false
            }
          }
        | {
            Args: {
              p_board_item_id: string
              p_channel?: string
              p_external_link?: string
              p_notes?: string
              p_outcome?: string
              p_published_at?: string
              p_submitted_at?: string
            }
            Returns: {
              board_item_id: string
              channel: string
              created_at: string
              external_link: string | null
              id: number
              notes: string | null
              outcome: string
              published_at: string | null
              submitted_at: string | null
              updated_at: string
              updated_by: string
            }
            SetofOptions: {
              from: "*"
              to: "publication_submission_events"
              isOneToOne: true
              isSetofReturn: false
            }
          }
      upsert_tribe_deliverable: {
        Args: {
          p_artifact_id?: string
          p_assigned_member_id?: string
          p_cycle_code?: string
          p_description?: string
          p_due_date?: string
          p_id?: string
          p_status?: string
          p_title?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      volunteer_funnel_summary: { Args: { p_cycle?: number }; Returns: Json }
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
