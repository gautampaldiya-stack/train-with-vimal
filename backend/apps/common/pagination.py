from rest_framework.pagination import CursorPagination, PageNumberPagination


class DefaultPagination(PageNumberPagination):
    """Page numbers for tables (design shows "1–10 of 41" and a pager)."""

    page_size = 25
    page_size_query_param = "page_size"
    max_page_size = 100


class TimelineCursorPagination(CursorPagination):
    """Cursor paging for big, ever-growing feeds (activity, logs, notifications).

    Stays fast at millions of rows because it never counts or offsets.
    """

    page_size = 30
    page_size_query_param = "page_size"
    max_page_size = 100
    ordering = "-created_at"
