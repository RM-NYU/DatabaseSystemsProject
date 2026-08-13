# DatabaseSystemsProject
Project Repo for the Database Systems Project Summer 2026 - Ronojoy Mitra

Overview:
A four-part project building an Enterprise Data Architecture for an insurance company, from conceptual model through to a working application. The business goal is to help the insurer anticipate chronic disease burden from social, economic and environmental factors, so that the resulting insight can inform product design, territory planning and the quote-to-policy workflow.

Repository Structure: 
Part 1  - Modeling, Conceptual entity relationship model
Part 2 - Logical Schema, Hybrid data extension
Part 3 - Physical Design, Machine Learning models
Part 4 - Data driven pipeline module and web application

Setup: 
  Prerequisites:
    PostgreSQL 16
    Python 3.11 or later
    pgAdmin 4 

  Python packages
    bash
    pip install pandas scikit-learn sqlalchemy "psycopg[binary]" streamlit jupyter matplotlib

  Database
  
    Create a database, then run the SQL scripts in order:
    
    1. part2-logical-schema/part2_trimmed_schema.sql     creates the eda schema
    2. part2-logical-schema/part2_load_data.sql          reference data + staging
    3. part3-physical-ml/part3_physical_design.sql       indexes, partitions, matview
    4. part3-physical-ml/part3_load_synthea.sql          synthetic patient population
    5. part4-application/part4_module_table.sql          pipeline support table
    
  Connection string
  
    Both Part 4 programs read a DB_URL constant near the top of the file. Replace the placeholder password with your own before running:
    
    python
    DB_URL = "postgresql+psycopg://postgres:YOUR_PASSWORD@localhost:5432/insurancecomp2_eda"
    
    In a real deployment this would come from an environment variable or a secret store rather than the source file.
  
  Running
    The pipeline module
      bash
      cd part4-application
      python part4_pipeline.py            # re-trains only if a source has changed
      python part4_pipeline.py --force    # re-trains regardless
      
      A run where nothing has changed exits in about a tenth of a second. A full re-aggregation and re-train takes six to eight seconds.
      
      To see change detection work, append a row to data/aqi_ny_county.csv and run again — the module detects the changed hash and re-trains.
  
    The application
      bash
      cd part4-application
      streamlit run part4_app_simple.py
      
      Opens at http://localhost:8501. Enter applicant details and a New York ZIP code; the application resolves the ZIP to a county, retrieves that county's machine-learning risk           tier, calculates a premium and issues a policy.
      
    The machine learning notebook
      bash
      cd part3-physical-ml
      jupyter notebook part3_ml_notebook.ipynb
      
      An executed HTML export is included, so the results can be read without running anything.


Data sources
  Source	
    CDC/ATSDR Social Vulnerability Index	Public domain (US Government)
    CDC PLACES	Public domain (US Government)
    EPA Air Quality Data	Public domain (US Government)
    Synthea	Apache 2.0
    
    The member population is synthetic. 
