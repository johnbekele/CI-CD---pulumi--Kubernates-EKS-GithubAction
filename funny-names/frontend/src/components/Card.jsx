import React from 'react';

const Card = ({ title, description, buttonText, onButtonClick }) => {
  return (
    <div style={styles.card}>
      <h3 className='name'>{title}</h3>
      <p>{description}</p>
      <button onClick={onButtonClick} style={styles.button}>
        {buttonText}
      </button>
    </div>
  );
};

// Basic inline styling for demonstration
const styles = {
  card: {
    border: '1px solid #ddd',
    borderRadius: '8px',
    padding: '20px',
    maxWidth: '300px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
    fontFamily: 'Arial, sans-serif'
  },
  button: {
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    padding: '10px 15px',
    borderRadius: '4px',
    cursor: 'pointer'
  },
  name:{
   margin: "0px ,50px"
  }
};

export default Card;
