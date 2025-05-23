from typing import Any, Dict, List, Optional

import torch
from sentence_transformers import CrossEncoder


class RerankerService:
    """Service for reranking retrieval results"""

    def __init__(self, model_name: str = "cross-encoder/ms-marco-MiniLM-L-6-v2"):
        """
        Initialize the reranker service with a specific model

        Args:
            model_name: Name of the reranker model to use
                Options include:
                - "cross-encoder/ms-marco-MiniLM-L-6-v2" (fast)
                - "BAAI/bge-reranker-base" (balanced)
                - "BAAI/bge-reranker-large" (more accurate)
        """
        self.model_name = model_name
        # Load model with half precision for faster inference if supported
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model = CrossEncoder(model_name, device=self.device)

        # For faster inference with larger batch sizes on GPU
        if self.device == "cuda":
            self.model.model = self.model.model.half()

    async def rerank(
        self, query: str, documents: List[Dict[str, Any]], top_k: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Rerank documents based on relevance to the query

        Args:
            query: The search query
            documents: List of document dictionaries from the retriever
            top_k: Number of top documents to return (None for all)

        Returns:
            Reranked list of documents with scores
        """
        if not documents:
            return []

        # Create document-query pairs for scoring
        doc_query_pairs = [(query, doc.get("content", "")) for doc in documents]

        # Get relevance scores
        scores = self.model.predict(doc_query_pairs)

        # Add scores to documents
        for i, doc in enumerate(documents):
            doc["reranker_score"] = float(scores[i])
            # If there was a previous score, we can combine them
            if "score" in doc:
                # Weighted combination of retriever and reranker scores
                doc["final_score"] = 0.3 * doc["score"] + 0.7 * doc["reranker_score"]
            else:
                doc["final_score"] = doc["reranker_score"]

        # Sort by final score
        reranked_docs = sorted(
            documents, key=lambda d: d.get("final_score", 0), reverse=True
        )

        # Return top_k if specified
        if top_k is not None:
            return reranked_docs[:top_k]

        return reranked_docs
