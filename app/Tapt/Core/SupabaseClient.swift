import Foundation
import Supabase

/// Shared Supabase client. URL + publishable key are public-safe:
/// RLS protects all data, so these can live in the client bundle.
/// Project: qfwiizvqxrhjlthbjosz (us-east-2).
enum Supa {
    static let url = URL(string: "https://qfwiizvqxrhjlthbjosz.supabase.co")!
    static let publishableKey = "sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF"
    static let authRedirectURL = URL(string: "tapt://auth-callback")!

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey
    )
}
