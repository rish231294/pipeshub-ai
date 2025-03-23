from typing import Dict, List, Any
import json
from dataclasses import dataclass

@dataclass
class ChatDocCitation:
    content: str
    metadata: Dict[str, Any]
    docindex: int

def process_citations(llm_response, documents: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Process the LLM response and extract citations from relevant documents.
    
    Args:
        llm_response: JSON string from LLM containing documentIndexes
        documents: List of document dictionaries with content and metadata
        
    Returns:
        Dict containing processed response with citations
    """
    try:
        # Parse the LLM response
        response_data = json.loads(llm_response.content)
        print(response_data, "response_data")
        print(documents, "documents")
        # Extract document indexes (1-based indexing from template)
        doc_indexes = [int(idx) - 1 for idx in response_data.get("recordIndexes", [])]
        print(doc_indexes, "doc_indexes")
        # Get citations from referenced documents
        citations = []
        for idx in doc_indexes:
            print("=====")
            print(idx, "idx = ", len(documents))
            print("=====")
            if 0 <= idx < len(documents):
                doc = documents[idx]
                print(doc, "doc")
                citation = ChatDocCitation(
                    content=doc['content'],
                    metadata=doc['metadata'],
                    docindex=idx+1
                )
                citations.append(citation)
        print(citations, "citations")

        # Add citations to response
        response_data["citations"] = [
            {
                "content": cit.content,
                "docindex": cit.docindex,
                "metadata": cit.metadata,
                "citation_type": "vectordb|document"
            }
            for cit in citations
        ]
        
        return response_data
        
    except json.JSONDecodeError:
        return {
            "error": "Failed to parse LLM response",
            "raw_response": llm_response
        }
    except Exception as e:
        return {
            "error": f"Citation processing failed: {str(e)}",
            "raw_response": llm_response
        }