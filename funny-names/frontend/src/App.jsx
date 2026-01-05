import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import axios from "axios";
import './App.css'
import Card from './components/Card';

import { ProductCard } from 'vibekit-ui';



function  App() {
  const [count, setCount] = useState(0)
  const [name ,setName]=useState("abebe ;)")


const  handleClick= async () =>{
    const reques=await axios.get("http://127.0.0.1:8000/");
    const response=reques.data.name
    setName(response)
  }


  

  
 return (
    <div className='container'>
     <Card 
      title={name}
      description="funny name :)"
      buttonText="click me to see fuuny name  "
      onButtonClick={handleClick}
    />
    </div>
  );

}

export default App
