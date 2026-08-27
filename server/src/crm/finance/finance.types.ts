export interface ExpenseRow {
  id: string;
  amount: string | number;
  category: string;
  description: string | null;
  branch_id: string | null;
  branch_name: string | null;
  created_at: Date | string;
}

export interface ExpectedPaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  due_date: Date | string | null;
  status: string;
  description: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

export interface StudentBalanceRow {
  student_id: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  total_paid: string | number;
  total_cost: string | number;
  total_adjustments?: string | number;
  balance: string | number;
  updated_at: Date | string;
}

export interface LedgerRow {
  id: string;
  kind: string;
  amount: string | number;
  description: string | null;
  method: string | null;
  branch_name: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  occurred_at: Date | string;
  invoice_number: string | null;
  status: string;
  editable: boolean;
}

export type LedgerRowWithTotals = LedgerRow & {
  income_total?: string | number;
  outcome_total?: string | number;
};
